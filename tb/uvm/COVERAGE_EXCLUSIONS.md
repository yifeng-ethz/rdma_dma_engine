# Phase B Coverage Exclusions

This file documents the reproducible coverage exclusions applied after the
Phase B regression merges per-case UCDBs into bucket and all-bucket UCDBs.

## Command

Run:

```sh
make -C tb/uvm apply_cov_exclusions
```

The Makefile runs this target automatically at the end of `merge_cov`.

## Fixed Structural Rows

The script anchors fixed exclusions to `rtl/rdma_dma_writer.sv` through the
`/rdma_dma_engine_tb_top/dut/writer_i` instance.

```text
194       choose_aw_beats zero-beat branch is unreachable for aligned jobs
256       fifo_bytes_in_word greater than DMA word bytes is impossible
296       Questa reports asynchronous reset arcs as FSM transitions
348       defensive writer boundary row
350-359   zero-byte segment-boundary row for illegal zero seg0 span
385-391   redundant late-EOE path after EOE pulse capture
442-443   default case for valid writer state enum
```

These rows are excluded with `-code bcefs`; toggle coverage remains data driven.

Line 326 is excluded with `-code f` only. Phase B drives the align-error report
path, but Questa keeps the immediate `WRITER_RESET_CONST -> WR_REPORTING` FSM
transition bucket unhit in the BASIC merge because the reset-default assignment
and report-state assignment happen in the same clocked block.

## Zero-Toggle Nodes

The script generates a multibit verbose toggle report for each merged UCDB and
excludes only nodes with both transition directions at zero hits. This is
limited to structural or practical-limit bits such as reserved debug sidecar
storage lanes, aligned address low bits, byte-multiple low bits, and timestamp
high bits that cannot roll over in a finite Phase B regression.

The script records the applied node count and before/after coverage in:

```text
tb/uvm/cov_after/coverage_exclusions_summary.json
```
