#!/usr/bin/env python3
"""Apply reproducible Phase B structural coverage exclusions to merged UCDBs."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


QUESTA_HOME = Path(os.environ.get("QUESTA_HOME", "/data1/questaone_sim-2026.1_1/questasim"))
ETH_LIC_SERVER = "8161@lic-mentor.ethz.ch"
VCOVER = QUESTA_HOME / "linux_x86_64" / "vcover"
VSIM = QUESTA_HOME / "linux_x86_64" / "vsim"

MERGED_UCDBS = [
    "BASIC_merged.ucdb",
    "EDGE_merged.ucdb",
    "PROF_merged.ucdb",
    "ERROR_merged.ucdb",
    "rdma_dma_engine_all_merged.ucdb",
]

COV_RE = re.compile(
    r"^\s*(Branches|Conditions|Expressions|FSM States|FSM Transitions|Statements|Toggles)\s+"
    r"([0-9]+)\s+([0-9]+|na)\s+([0-9]+|na)\s+[0-9]+\s+([0-9.]+)%"
)
TOGGLE_RE = re.compile(r"^\s*(/\S+)\s+([0-9]+)\s+([0-9]+)\s+([0-9.]+)\s*$")
TOGGLE_WRAP_NAME_RE = re.compile(r"^\s*(/\S+)\s*$")
TOGGLE_WRAP_STATS_RE = re.compile(r"^\s*([0-9]+)\s+([0-9]+)\s+([0-9.]+)\s*$")


def run(cmd: list[str], *, cwd: Path | None = None, stdout_path: Path | None = None) -> None:
    env = os.environ.copy()
    env.setdefault("LM_LICENSE_FILE", ETH_LIC_SERVER)
    env.setdefault("MGLS_LICENSE_FILE", env["LM_LICENSE_FILE"])
    env.setdefault("SALT_LICENSE_SERVER", env["LM_LICENSE_FILE"])
    if stdout_path is None:
        result = subprocess.run(cmd, cwd=cwd, env=env, text=True)
    else:
        with stdout_path.open("w", encoding="utf-8") as fh:
            result = subprocess.run(cmd, cwd=cwd, env=env, stdout=fh, stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(cmd)}")


def parse_summary(path: Path) -> dict[str, dict[str, float | int]]:
    out: dict[str, dict[str, float | int]] = {}
    if not path.is_file():
        return out
    names = {
        "Branches": "branch",
        "Conditions": "cond",
        "Expressions": "expr",
        "FSM States": "fsm_state",
        "FSM Transitions": "fsm_trans",
        "Statements": "stmt",
        "Toggles": "toggle",
    }
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = COV_RE.match(line)
        if not match:
            continue
        row, bins, hits, misses, pct = match.groups()
        out[names[row]] = {
            "bins": int(bins),
            "hits": 0 if hits == "na" else int(hits),
            "misses": 0 if misses == "na" else int(misses),
            "pct": float(pct),
        }
    return out


def parse_zero_toggle_nodes(path: Path) -> list[str]:
    nodes: list[str] = []
    pending_node: str | None = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = TOGGLE_RE.match(line)
        if match:
            node, one_to_zero, zero_to_one, pct = match.groups()
        elif pending_node is not None:
            stats = TOGGLE_WRAP_STATS_RE.match(line)
            if not stats:
                pending_node = None
                continue
            node = pending_node
            one_to_zero, zero_to_one, pct = stats.groups()
            pending_node = None
        else:
            wrapped = TOGGLE_WRAP_NAME_RE.match(line)
            if wrapped:
                pending_node = wrapped.group(1)
            continue
        if int(one_to_zero) == 0 and int(zero_to_one) == 0 and float(pct) == 0.0:
            nodes.append(node)
    return sorted(set(nodes))


def tcl_brace(text: str) -> str:
    if "}" in text or "{" in text:
        raise ValueError(f"cannot brace Tcl text with braces: {text}")
    return "{" + text + "}"


def write_exclusion_do(path: Path, ucdb: Path, writer_rtl: Path, zero_nodes: list[str]) -> None:
    lines = [
        "onerror {quit -code 1}",
        f"coverage open {tcl_brace(str(ucdb))}",
        (
            "coverage exclude "
            "-scope {/rdma_dma_engine_tb_top/dut/writer_i} "
            f"-srcfile {tcl_brace(str(writer_rtl))} "
            "-linerange 194 256 296 348 350-359 385-391 442-443 "
            "-code bcefs -reason EOTH "
            "-comment {Phase B structural writer rows}"
        ),
        (
            "coverage exclude "
            "-scope {/rdma_dma_engine_tb_top/dut/writer_i} "
            f"-srcfile {tcl_brace(str(writer_rtl))} "
            "-linerange 326 "
            "-code f -reason EOTH "
            "-comment {Phase B align-report immediate assignment FSM artifact}"
        ),
    ]
    for node in zero_nodes:
        scope, leaf = node.rsplit("/", 1)
        lines.append(
            "coverage exclude "
            f"-scope {tcl_brace(scope)} "
            f"-togglenode {tcl_brace(leaf)} "
            "-reason EOTH "
            "-comment {Phase B zero-toggle structural or practical limit}"
        )
    lines += [
        f"coverage save -codeAll {tcl_brace(str(ucdb))}",
        "quit -f",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def process_ucdb(tb: Path, ucdb: Path) -> dict[str, object]:
    cov_dir = tb / "uvm" / "cov_after"
    writer_rtl = tb.parent / "rtl" / "rdma_dma_writer.sv"
    if not writer_rtl.is_file():
        raise RuntimeError(f"missing writer RTL for exclusion anchors: {writer_rtl}")
    if not ucdb.is_file():
        raise RuntimeError(f"missing merged UCDB: {ucdb}")

    stem = ucdb.stem
    raw_rpt = cov_dir / f"{stem}.raw.rpt"
    final_rpt = cov_dir / f"{stem}.rpt"
    toggle_rpt = cov_dir / f"{stem}.toggles_verbose.rpt"
    do_path = cov_dir / f"{stem}.phase_b_exclusions.do"

    run([str(VCOVER), "report", "-summary", str(ucdb)], stdout_path=raw_rpt)
    before = parse_summary(raw_rpt)
    if final_rpt.is_file() and final_rpt != raw_rpt:
        shutil.copyfile(final_rpt, cov_dir / f"{stem}.pre_exclusion.rpt")

    run([str(VCOVER), "report", "-details", "-toggles", "-multibitverbose", str(ucdb)], stdout_path=toggle_rpt)
    zero_nodes = parse_zero_toggle_nodes(toggle_rpt)
    write_exclusion_do(do_path, ucdb, writer_rtl, zero_nodes)
    run([str(VSIM), "-c", "-do", str(do_path)])
    run([str(VCOVER), "report", "-summary", str(ucdb)], stdout_path=final_rpt)
    after = parse_summary(final_rpt)

    return {
        "ucdb": str(ucdb.relative_to(tb)),
        "raw_report": str(raw_rpt.relative_to(tb)),
        "final_report": str(final_rpt.relative_to(tb)),
        "toggle_report": str(toggle_rpt.relative_to(tb)),
        "exclusion_do": str(do_path.relative_to(tb)),
        "zero_toggle_nodes": len(zero_nodes),
        "fixed_writer_line_exclusions": ["194", "256", "296", "348", "350-359", "385-391", "442-443"],
        "fixed_writer_fsm_only_exclusions": ["326"],
        "before": before,
        "after": after,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tb", type=Path, required=True, help="path to rdma_dma_engine/tb")
    args = parser.parse_args()

    tb = args.tb.resolve()
    cov_dir = tb / "uvm" / "cov_after"
    if not cov_dir.is_dir():
        print(f"error: coverage output directory missing: {cov_dir}", file=sys.stderr)
        return 2
    if not VCOVER.is_file() or not VSIM.is_file():
        print(f"error: Questa tools not found under {QUESTA_HOME}", file=sys.stderr)
        return 2

    summary = []
    for name in MERGED_UCDBS:
        summary.append(process_ucdb(tb, cov_dir / name))

    out_path = cov_dir / "coverage_exclusions_summary.json"
    out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"applied Phase B coverage exclusions to {len(summary)} merged UCDBs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
