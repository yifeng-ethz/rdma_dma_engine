`ifndef RDMA_DMA_ENGINE_SCOREBOARD_SV
`define RDMA_DMA_ENGINE_SCOREBOARD_SV

class rdma_dma_engine_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(rdma_dma_engine_scoreboard)

  uvm_analysis_imp_opq #(opq_axis_pkg::opq_axis_item, rdma_dma_engine_scoreboard) opq_imp;
  uvm_analysis_imp_axi #(axi4_write_pkg::axi4_write_item, rdma_dma_engine_scoreboard) axi_imp;
  uvm_analysis_imp_job #(job_pkg::job_item, rdma_dma_engine_scoreboard) job_imp;
  uvm_analysis_imp_dbg1 #(dbg1_taps_item, rdma_dma_engine_scoreboard) dbg1_imp;
  uvm_analysis_imp_dbg2 #(dbg2_writer_item, rdma_dma_engine_scoreboard) dbg2_imp;

  string case_id;
  string scorecard_path;
  int unsigned debug_level;
  int unsigned mismatch_count;
  int unsigned opq_count;
  int unsigned aw_count;
  int unsigned w_count;
  int unsigned b_count;
  int unsigned job_done_count;
  int unsigned dbg1_sample_count;
  int unsigned dbg2_emit_count;
  int unsigned expected_byte_count;
  int unsigned current_aw_beats_remaining;
  bit saw_eoe;
  bit allow_non_okay_bresp;

  typedef struct packed {
    bit [255:0] data;
    bit [31:0] strb;
    int unsigned valid_slots;
  } beat_t;

  typedef struct packed {
    bit [3:0] lane;
    bit [31:0] hit_id;
    bit [63:0] source_ts;
    bit [31:0] sequence_no;
  } lineage_t;

  typedef struct packed {
    bit [63:0] total_bytes;
    bit [31:0] seg0_bytes;
    bit [31:0] seg1_bytes;
    bit [15:0] status_value;
    bit [15:0] status_mask;
    bit [15:0] sqe_id;
  } job_expect_t;

  beat_t expected_beats[$];
  lineage_t expected_lineage[$];
  lineage_t observed_dbg2[$];
  job_expect_t expected_jobs[$];
  bit [255:0] pack_data;
  bit [31:0] pack_strb;
  int unsigned pack_slot;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    case_id = "UNKNOWN";
    scorecard_path = "";
    debug_level = 1;
    reset_model();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    opq_imp = new("opq_imp", this);
    axi_imp = new("axi_imp", this);
    job_imp = new("job_imp", this);
    dbg1_imp = new("dbg1_imp", this);
    dbg2_imp = new("dbg2_imp", this);
  endfunction

  function void reset_model();
    mismatch_count = 0;
    opq_count = 0;
    aw_count = 0;
    w_count = 0;
    b_count = 0;
    job_done_count = 0;
    dbg1_sample_count = 0;
    dbg2_emit_count = 0;
    expected_byte_count = 0;
    current_aw_beats_remaining = 0;
    saw_eoe = 1'b0;
    allow_non_okay_bresp = 1'b0;
    expected_beats.delete();
    expected_lineage.delete();
    observed_dbg2.delete();
    expected_jobs.delete();
    pack_data = '0;
    pack_strb = '0;
    pack_slot = 0;
  endfunction

  function void configure_case(input string id, input string path, input int unsigned dbg);
    case_id = id;
    scorecard_path = path;
    debug_level = dbg;
  endfunction

  function void set_allow_non_okay_bresp(input bit allow_errors);
    allow_non_okay_bresp = allow_errors;
  endfunction

  function void expect_job(
    input bit [63:0] total_bytes,
    input bit [31:0] seg0_bytes,
    input bit [31:0] seg1_bytes,
    input bit [15:0] status_value,
    input bit [15:0] status_mask,
    input bit [15:0] sqe_id
  );
    job_expect_t exp;
    exp.total_bytes = total_bytes;
    exp.seg0_bytes = seg0_bytes;
    exp.seg1_bytes = seg1_bytes;
    exp.status_value = status_value;
    exp.status_mask = status_mask;
    exp.sqe_id = sqe_id;
    expected_jobs.push_back(exp);
  endfunction

  function void clear_current_job_model();
    expected_byte_count = 0;
    saw_eoe = 1'b0;
    expected_beats.delete();
    pack_data = '0;
    pack_strb = '0;
    pack_slot = 0;
    current_aw_beats_remaining = 0;
  endfunction

  function lineage_t canonical_lineage(input opq_axis_pkg::opq_axis_item item);
    lineage_t lin;
    lin.lane = (debug_level >= 2) ? item.lane : 4'h0;
    lin.hit_id = (debug_level >= 2 && item.hit_id != 32'h0) ? item.hit_id : (opq_count + 1);
    lin.source_ts = (debug_level >= 2 && item.source_ts != 64'h0) ? item.source_ts : (opq_count + 1);
    if (debug_level >= 2 && item.sequence_no != 32'h0) begin
      lin.sequence_no = item.sequence_no;
    end else if (item.data[31:24] == 8'h00 && item.data[23:8] != 16'h0000) begin
      lin.sequence_no = {16'h0000, item.data[23:8]};
    end else begin
      lin.sequence_no = 32'd1;
    end
    return lin;
  endfunction

  function void write_opq(opq_axis_pkg::opq_axis_item item);
    lineage_t lin;
    beat_t beat;
    int unsigned byte_base;

    lin = canonical_lineage(item);
    expected_lineage.push_back(lin);
    pack_data[pack_slot*32 +: 32] = item.data;
    byte_base = pack_slot * 4;
    for (int unsigned i = 0; i < 4; i++)
      pack_strb[byte_base + i] = 1'b1;
    pack_slot++;
    opq_count++;
    expected_byte_count += 4;
    if (item.eoe)
      saw_eoe = 1'b1;

    if (item.eoe || pack_slot == RDMA_DMA_OPQ_PER_BEAT) begin
      beat.data = pack_data;
      beat.strb = pack_strb;
      beat.valid_slots = pack_slot;
      expected_beats.push_back(beat);
      pack_data = '0;
      pack_strb = '0;
      pack_slot = 0;
    end
  endfunction

  function void note_mismatch(input string msg);
    mismatch_count++;
    `uvm_error("SCB", $sformatf("%s %s", case_id, msg))
  endfunction

  function void write_axi(axi4_write_pkg::axi4_write_item item);
    beat_t exp;
    int unsigned beats_before_w;
    bit expected_last;
    if (item.is_aw) begin
      aw_count++;
      if (current_aw_beats_remaining != 0)
        note_mismatch("new AW observed before previous W burst completed");
      current_aw_beats_remaining = item.len + 1;
      if (item.len > 8'd15)
        note_mismatch($sformatf("AWLEN exceeds MAX_BURST cap: %0d", item.len));
      if (item.size != 3'd5)
        note_mismatch($sformatf("AWSIZE mismatch got=%0d expected=5", item.size));
      if (item.burst != 2'b01)
        note_mismatch($sformatf("AWBURST mismatch got=%0d expected=1", item.burst));
      if (item.addr[4:0] != 5'h00)
        note_mismatch($sformatf("AWADDR not 32B aligned: 0x%016h", item.addr));
      if ((int'(item.addr[11:0]) + ((int'(item.len) + 1) * RDMA_DMA_BYTES)) > 4096)
        note_mismatch($sformatf("AW burst crosses 4KB page addr=0x%016h len=%0d", item.addr, item.len));
    end
    if (item.is_w) begin
      w_count++;
      beats_before_w = current_aw_beats_remaining;
      if (beats_before_w == 0) begin
        note_mismatch("W beat observed without an active AW burst");
      end else begin
        expected_last = (beats_before_w == 1);
        current_aw_beats_remaining = beats_before_w - 1;
        if (item.last !== expected_last)
          note_mismatch($sformatf("WLAST mismatch got=%0d expected=%0d", item.last, expected_last));
      end
      if (expected_beats.size() == 0) begin
        note_mismatch("W beat observed with empty expected beat queue");
      end else begin
        exp = expected_beats.pop_front();
        if (item.data !== exp.data)
          note_mismatch($sformatf(
            "WDATA mismatch got=0x%064h expected=0x%064h", item.data, exp.data));
        if (item.strb !== exp.strb)
          note_mismatch($sformatf("WSTRB mismatch got=0x%08h expected=0x%08h", item.strb, exp.strb));
      end
    end
    if (item.is_b) begin
      b_count++;
      if (item.resp != axi4_write_pkg::AXI_RESP_OKAY && !allow_non_okay_bresp)
        note_mismatch($sformatf("BRESP non-OKAY when not expected: %0d", item.resp));
    end
  endfunction

  function void write_job(job_pkg::job_item item);
    job_expect_t exp;
    job_done_count++;
    if (expected_jobs.size() != 0) begin
      exp = expected_jobs.pop_front();
      if (item.bytes_written_total != exp.total_bytes)
        note_mismatch($sformatf("job bytes mismatch got=%0d expected=%0d",
                                item.bytes_written_total, exp.total_bytes));
      if (item.seg0_bytes_written != exp.seg0_bytes)
        note_mismatch($sformatf("seg0 bytes mismatch got=%0d expected=%0d",
                                item.seg0_bytes_written, exp.seg0_bytes));
      if (item.seg1_bytes_written != exp.seg1_bytes)
        note_mismatch($sformatf("seg1 bytes mismatch got=%0d expected=%0d",
                                item.seg1_bytes_written, exp.seg1_bytes));
      if ((item.status & exp.status_mask) !== (exp.status_value & exp.status_mask))
        note_mismatch($sformatf("status mismatch got=0x%04h expected(masked)=0x%04h mask=0x%04h",
                                item.status, exp.status_value, exp.status_mask));
      if (item.sqe_id_echo !== exp.sqe_id)
        note_mismatch($sformatf("sqe_id_echo=0x%04h expected=0x%04h", item.sqe_id_echo, exp.sqe_id));
    end else begin
      if (item.bytes_written_total != expected_byte_count)
        note_mismatch($sformatf("job bytes mismatch got=%0d expected=%0d",
                                item.bytes_written_total, expected_byte_count));
      if (item.seg0_bytes_written != expected_byte_count)
        note_mismatch($sformatf("seg0 bytes mismatch got=%0d expected=%0d",
                                item.seg0_bytes_written, expected_byte_count));
      if (!item.status[RDMA_DMA_ST_SEG0_ONLY])
        note_mismatch("SEG0_ONLY status bit not set for single-segment smoke job");
      if (saw_eoe && !item.status[RDMA_DMA_ST_EOE])
        note_mismatch("EOE status bit not set after OPQ tlast");
    end
    clear_current_job_model();
  endfunction

  function void write_dbg1(dbg1_taps_item item);
    dbg1_sample_count++;
  endfunction

  function void write_dbg2(dbg2_writer_item item);
    lineage_t exp;
    lineage_t got;
    dbg2_emit_count++;
    got.lane = item.lane;
    got.hit_id = item.hit_id;
    got.source_ts = item.source_ts;
    got.sequence_no = item.sequence_no;
    observed_dbg2.push_back(got);
    if (dbg2_emit_count > expected_lineage.size()) begin
      note_mismatch("DEBUG=2 writer lineage emitted with no expected ingress entry");
      return;
    end
    exp = expected_lineage[dbg2_emit_count - 1];
    if (got != exp) begin
      note_mismatch($sformatf(
        "DEBUG=2 lineage mismatch idx=%0d got=(%0d,%0d,%0d,%0d) expected=(%0d,%0d,%0d,%0d)",
        dbg2_emit_count - 1, got.lane, got.hit_id, got.source_ts, got.sequence_no,
        exp.lane, exp.hit_id, exp.source_ts, exp.sequence_no));
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (expected_beats.size() != 0)
      note_mismatch($sformatf("expected beat queue residual=%0d", expected_beats.size()));
    if (pack_slot != 0)
      note_mismatch($sformatf("partial packer residual slot=%0d", pack_slot));
    if (current_aw_beats_remaining != 0)
      note_mismatch($sformatf("active AW burst residual beats=%0d", current_aw_beats_remaining));
    if (expected_jobs.size() != 0)
      note_mismatch($sformatf("expected job queue residual=%0d", expected_jobs.size()));
    if (debug_level >= 2 && dbg2_emit_count != expected_lineage.size())
      note_mismatch($sformatf("DEBUG=2 lineage residual got=%0d expected=%0d",
                              dbg2_emit_count, expected_lineage.size()));
    if (job_done_count == 0 && opq_count != 0)
      note_mismatch("OPQ traffic observed but no job_done was reported");
  endfunction

  function void write_scorecard();
    int fd;
    lineage_t lin;
    if (scorecard_path == "")
      return;
    fd = $fopen(scorecard_path, "w");
    if (fd == 0) begin
      `uvm_error("SCB", $sformatf("Could not open scorecard %s", scorecard_path))
      return;
    end
    $fwrite(fd, "{\n");
    $fwrite(fd, "  \"case_id\": \"%s\",\n", case_id);
    $fwrite(fd, "  \"debug_level\": %0d,\n", debug_level);
    $fwrite(fd, "  \"summary\": {\"opq\": %0d, \"aw\": %0d, \"w\": %0d, \"b\": %0d, \"job_done\": %0d, \"mismatches\": %0d},\n",
            opq_count, aw_count, w_count, b_count, job_done_count, mismatch_count);
    $fwrite(fd, "  \"lineage\": [\n");
    foreach (expected_lineage[idx]) begin
      lin = expected_lineage[idx];
      $fwrite(fd,
        "    {\"lane\": %0d, \"hit_id\": %0d, \"source_ts\": %0d, \"sequence_no\": %0d}%s\n",
        lin.lane, lin.hit_id, lin.source_ts, lin.sequence_no,
        (idx + 1 == expected_lineage.size()) ? "" : ",");
    end
    $fwrite(fd, "  ]\n");
    $fwrite(fd, "}\n");
    $fclose(fd);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    write_scorecard();
    `uvm_info("SCB", $sformatf(
      "%s summary opq=%0d aw=%0d w=%0d b=%0d done=%0d dbg1=%0d dbg2=%0d mismatches=%0d",
      case_id, opq_count, aw_count, w_count, b_count, job_done_count,
      dbg1_sample_count, dbg2_emit_count, mismatch_count), UVM_LOW)
  endfunction
endclass

`endif
