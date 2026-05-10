#!/usr/bin/env python3
"""Compare DEBUG=1 and DEBUG=2 rdma_dma_engine scorecards."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


LINEAGE_KEYS = ("lane", "hit_id", "source_ts", "sequence_no")


def load_scorecard(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise RuntimeError(f"missing scorecard: {path}") from None
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid JSON in {path}: {exc}") from exc


def tuple_from_entry(path: Path, index: int, entry: dict) -> tuple[int, int, int, int]:
    if not isinstance(entry, dict):
        raise RuntimeError(f"{path}: lineage[{index}] is not an object")
    values: list[int] = []
    for key in LINEAGE_KEYS:
        if key not in entry:
            raise RuntimeError(f"{path}: lineage[{index}] is missing {key}")
        try:
            values.append(int(entry[key]))
        except (TypeError, ValueError) as exc:
            raise RuntimeError(f"{path}: lineage[{index}].{key} is not an integer") from exc
    return (values[0], values[1], values[2], values[3])


def lineage_tuples(path: Path, data: dict) -> list[tuple[int, int, int, int]]:
    lineage = data.get("lineage")
    if not isinstance(lineage, list):
        raise RuntimeError(f"{path}: lineage is not a list")
    return [tuple_from_entry(path, index, entry) for index, entry in enumerate(lineage)]


def mismatch_count(path: Path, data: dict) -> int:
    summary = data.get("summary")
    if not isinstance(summary, dict):
        raise RuntimeError(f"{path}: summary is not an object")
    try:
        return int(summary.get("mismatches", 0))
    except (TypeError, ValueError) as exc:
        raise RuntimeError(f"{path}: summary.mismatches is not an integer") from exc


def discover_cases(root: Path) -> list[str]:
    dbg1_dir = root / "dbg1"
    dbg2_dir = root / "dbg2"
    dbg1_cases = {path.name.removesuffix(".scorecard.json") for path in dbg1_dir.glob("*.scorecard.json")}
    dbg2_cases = {path.name.removesuffix(".scorecard.json") for path in dbg2_dir.glob("*.scorecard.json")}
    return sorted(dbg1_cases & dbg2_cases)


def compare_case(root: Path, case_id: str) -> list[str]:
    dbg1_path = root / "dbg1" / f"{case_id}.scorecard.json"
    dbg2_path = root / "dbg2" / f"{case_id}.scorecard.json"
    dbg1_data = load_scorecard(dbg1_path)
    dbg2_data = load_scorecard(dbg2_path)
    failures: list[str] = []

    for path, data in ((dbg1_path, dbg1_data), (dbg2_path, dbg2_data)):
        mismatches = mismatch_count(path, data)
        if mismatches != 0:
            failures.append(f"{path}: summary.mismatches={mismatches}, expected 0")

    dbg1_lineage = lineage_tuples(dbg1_path, dbg1_data)
    dbg2_lineage = lineage_tuples(dbg2_path, dbg2_data)
    if len(dbg1_lineage) != len(dbg2_lineage):
        failures.append(
            f"{case_id}: lineage length differs dbg1={len(dbg1_lineage)} dbg2={len(dbg2_lineage)}"
        )
    for index, (dbg1_tuple, dbg2_tuple) in enumerate(zip(dbg1_lineage, dbg2_lineage)):
        if dbg1_tuple != dbg2_tuple:
            failures.append(
                f"{case_id}: lineage[{index}] differs dbg1={dbg1_tuple} dbg2={dbg2_tuple}"
            )
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Diff DEBUG=1 functional lineage against DEBUG=2 writer sidecar scorecards."
    )
    parser.add_argument("--root", type=Path, default=Path("cov_after"), help="coverage output root")
    parser.add_argument("--cases", nargs="*", help="case IDs to compare; default discovers common cases")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    cases = args.cases if args.cases else discover_cases(root)
    if not cases:
        print(f"cross_validate_dbg: no common scorecards found under {root}", file=sys.stderr)
        return 2
    failures: list[str] = []
    for case_id in cases:
        failures.extend(compare_case(root, case_id))
    if failures:
        print("cross_validate_dbg: DEBUG scorecard mismatches found", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"cross_validate_dbg: zero residual mismatch across {len(cases)} cases under {root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
