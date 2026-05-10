#!/usr/bin/env python3
"""Generate thin per-case Phase B UVM sequence and test wrappers."""

from __future__ import annotations

import re
from pathlib import Path


TB_DIR = Path(__file__).resolve().parents[2]
UVM_DIR = TB_DIR / "uvm"
BUCKET_DOCS = [
    ("BASIC", TB_DIR / "DV_BASIC.md"),
    ("EDGE", TB_DIR / "DV_EDGE.md"),
    ("PROF", TB_DIR / "DV_PROF.md"),
    ("ERROR", TB_DIR / "DV_ERROR.md"),
]


CASE_RE = re.compile(r"^\|\s*([BEPX][0-9]{3})\s*\|\s*([DR])\s*\|")


def collect_cases() -> list[tuple[str, str, str]]:
    cases: list[tuple[str, str, str]] = []
    for bucket, path in BUCKET_DOCS:
        for line in path.read_text(encoding="utf-8").splitlines():
            match = CASE_RE.match(line)
            if match:
                cases.append((bucket, match.group(1), match.group(2)))
    return cases


def guard(path: Path) -> str:
    token = re.sub(r"[^A-Za-z0-9]", "_", str(path)).upper()
    return f"RDMA_DMA_ENGINE_{token}"


def render_sequence(case_id: str) -> str:
    lower = case_id.lower()
    macro = f"SEQ_{case_id}_PHASE_B_SV"
    return f"""`ifndef {macro}
`define {macro}

class seq_{lower}_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_{lower}_phase_b)

  function new(string name = "seq_{lower}_phase_b");
    super.new(name);
    case_id = "{case_id}";
  endfunction
endclass

`endif
"""


def render_test(case_id: str) -> str:
    lower = case_id.lower()
    macro = f"TEST_{case_id}_PHASE_B_SV"
    return f"""`ifndef {macro}
`define {macro}

class test_{lower}_phase_b extends rdma_dma_engine_phase_b_test;
  `uvm_component_utils(test_{lower}_phase_b)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "{case_id}";
  endfunction

  function rdma_dma_phase_b_case_sequence create_case_sequence();
    seq_{lower}_phase_b seq;
    seq = seq_{lower}_phase_b::type_id::create("seq_{lower}_phase_b");
    return seq;
  endfunction
endclass

`endif
"""


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main() -> int:
    cases = collect_cases()
    if len(cases) != 512:
        raise SystemExit(f"expected 512 cases from DV bucket docs, got {len(cases)}")

    seq_dir = UVM_DIR / "sequences" / "generated"
    test_dir = UVM_DIR / "tests" / "generated"
    seq_include_lines = []
    test_include_lines = []
    make_entries = []
    case_ids = []

    for _bucket, case_id, _method in cases:
      lower = case_id.lower()
      seq_path = seq_dir / f"seq_{lower}_phase_b.sv"
      test_path = test_dir / f"test_{lower}_phase_b.sv"
      write(seq_path, render_sequence(case_id))
      write(test_path, render_test(case_id))
      seq_include_lines.append(f'`include "sequences/generated/{seq_path.name}"')
      test_include_lines.append(f'`include "tests/generated/{test_path.name}"')
      make_entries.append(f"  test_{lower}_phase_b:{case_id}")
      case_ids.append(case_id)

    write(seq_dir / "rdma_dma_phase_b_sequences.svh", "\n".join(seq_include_lines) + "\n")
    write(test_dir / "rdma_dma_phase_b_tests.svh", "\n".join(test_include_lines) + "\n")

    cases_text = " \\\n".join(make_entries)
    ids_text = " ".join(case_ids)
    write(
        UVM_DIR / "generated_cases.mk",
        "PHASE_B_CASES := \\\n" + cases_text + "\n\n" +
        "PHASE_B_CASE_IDS := " + ids_text + "\n",
    )
    print(f"generated {len(cases)} Phase B cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
