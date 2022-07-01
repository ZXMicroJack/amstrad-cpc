module nec765 (
  input wire clk,
  input wire rst_n,
  output reg[7:0] dout,
  input wire[7:0] din,
  input wire ce,
  input wire a0,
  input wire motorctl,
	input wire[7:0] disk_data_in,
	output wire[7:0] disk_data_out,
	output reg[31:0] disk_sr,
	input wire[31:0] disk_cr,
	input wire disk_data_clkout,
	input wire disk_data_clkin,
	input wire[1:0] disk_wp,
	input wire rd_n,
	input wire wr_n,
	output wire[31:0] debug
);

// FIFOS copied from WD1770 - not fully working
  wire[7:0] fifo_out_data;
  wire fifo_empty;
  reg fifo_reset = 1'b0;
  reg fifo_out_read = 1'b0;
  reg side_latched = 1'b0;
  wire fifo_in_full;

//wd1770 regs
  reg recnotfound = 0;
  reg drsel = 0;
  reg motor_on = 1'b0;

  // ctrl-module transfer state machine
  localparam IDLE = 0;
  localparam READSECT = 1;
  localparam READING = 2;
  localparam WRITING = 3;
  localparam COMMIT = 4;
  localparam SEEKING = 5;
  localparam READID = 6;
  localparam STARTWRITE = 7;
  reg[2:0] state = IDLE;
  
  // disk to cpu - reading
  fifo #(.RAM_SIZE(512), .ADDRESS_WIDTH(9)) fifo_in(
    .q(fifo_out_data),
    .d(disk_data_in),
    .clk(clk),
    .write(disk_data_clkin),
    .read(fifo_out_read),
    .reset(fifo_reset),
    .empty(fifo_empty));

  reg fifo_in_write = 1'b0;
  reg[9:0] fifo_in_size = 1'b0;
  wire fifo_out_empty;
  reg last_byte_read = 1'b0;

  // cpu to disk - writing
  fifo #(.RAM_SIZE(512), .ADDRESS_WIDTH(9)) fifo_out(
    .q(disk_data_out),
    .d(din),
    .clk(clk),
    .write(fifo_in_write),
    .read(disk_data_clkout),
    .reset(fifo_reset),
    .empty(fifo_out_empty),
    .full(fifo_in_full)
    );




reg prev_rd_n = 1'b1;
reg prev_wr_n = 1'b1;

// flags are hd,us1,us0 (head, unit select 1:0) note h is always = hd
// r = record = sector id
// n = number of bytes in sector
// c = cylinder
// h = head
// eot = final sector number
// gpl = gap length - can be ignored i think
// dtl = data length for read/write to/from sector
// st0 = {ic[1:0],seek_end, no_track0_equipment_fail, not_ready, hd_at_int, us[1:0]}
// st1 = {eoc, 0, data_error, overrun, 0, no_data, wp, missing_address_mark(notformatted)}
// st2 = {0, cm, crc_error, wrong_cylinder, scan_equal_hit, scan_not_found, bad_cylinder, missing_address_mark}
// st3 = {fault_fdd, wp_fdd, rdy_fdd, trk0_fdd, 2side_fdd, sideselect_fdd, us[1:0]}
// cm = data deleted mark encoutnered
// ic = 00:ok 01:abnormal_term 10:inv_command 11:physically_interrupted
// not_ready = could mean sector is not there on read/write command
// hd_at_int = which head used at interrupt
// eoc - end of cylinder - try to find sector beyond last one

// msr = {rfm, dio, exm, busy, fdbusy[3:0]}
// rfm = transfer pending
// dio = to cpu
// exm = execution mode - busy doing something.
// fdc = busy - command in progress

// instructions have bits {mt, mf, sk, ins[4:0]}
//  mt = multi-track - both sides - probably not needed with cpc
//  mf = fm or mfm(1) mode
//  sk = skip deleted data address mark

localparam READ_DATA          = 5'h06; // rx:f,c,h,r,n,eot,gpl,dtl tx:st0,st1,st2,c,h,r,n
localparam READ_DELETED_DATA  = 5'h0c; // rx:f,c,h,r,n,eot,gpl,dtl tx:st0,st1,st2,c,h,r,n
localparam WRITE_DATA         = 5'h05; // rx:f,c,h,r,n,eot,gpl,dtl tx:st0,st1,st2,c,h,r,n
localparam WRITE_DELETED_DATA = 5'h09; // rx:f,c,h,r,n,eot,gpl,dtl tx:st0,st1,st2,c,h,r,n

localparam READ_TRACK         = 5'h02; // rx:f,c,h,r,n,eot,gpl,dtl tx:st0,st1,st2,c,h,r,n
localparam READ_ID            = 5'h0a; // rx:f                     tx:st0,st1,st2,c,h,r,n
localparam FORMAT_TRACK       = 5'h0d; // rx:f,n,sc,gpl,d          tx:st0,st1,st2,c,h,r,n
localparam SCAN_EQUAL         = 5'h11; // rx:f,c,h,r,n,eot,gpl,dtl tx:st0,st1,st2,c,h,r,n

localparam SCAN_LEQUAL        = 5'h19; // rx:f,c,h,r,n,eot,gpl,dtl tx:st0,st1,st2,c,h,r,n
localparam SCAN_HEQUAL        = 5'h1d; // rx:f,c,h,r,n,eot,gpl,dtl tx:st0,st1,st2,c,h,r,n
localparam RECALIBRATE        = 5'h07; // rx:f                     tx:

localparam SENSE_INT_STATUS   = 5'h08; // rx:                      tx:sto,pcn
localparam SPECIFY            = 5'h03; // rx:srt-hut,hlt-nd        tx:
localparam SENSE_DRIVE_STATUS = 5'h04; // rx:f                     tx:st3
localparam SEEK               = 5'h0f; // rx:f,ncn                 tx:
localparam INVALID_INS        = 5'h1f;

localparam STATUS_IDLE = 0;
localparam STATUS_CMD = 1;
localparam STATUS_EXEC = 2;
localparam STATUS_RX = 3;

reg[1:0] status = STATUS_IDLE;

// reg[7:0] results[0:7];
reg[2:0] results_len = 0;
reg[2:0] results_pos = 0;

reg[7:0] params[0:10];
reg[3:0] params_len = 0;
reg[3:0] params_pos = 0;

wire rfm = (status == STATUS_IDLE && state != SEEKING) || 
  (status == STATUS_EXEC && state == READING && !last_byte_read) ||
  (status == STATUS_EXEC && ins[4:0] == WRITE_DATA && fifo_in_size != 512) ||
  (status == STATUS_RX && results_len != results_pos) ||
  (status == STATUS_CMD && params_len != params_pos);
wire dio = status == STATUS_RX || (status == STATUS_EXEC && ins[4:0] == READ_DATA);
wire exm = status == STATUS_EXEC;
wire busy = status != STATUS_IDLE;
reg[1:0] fdcbusy = 2'b00;
reg[7:0] intstat0 = 8'h00;
reg[7:0] intstat1 = 8'h00;
reg[1:0] rdy_fdd = 2'b00;
reg[7:0] pcn = 8'h00;
wire not_ready[1:0] = {!disk_cr[6], !disk_cr[5]};

reg[7:0] ins;

reg bad_cylinder = 1'b0;
reg data_error = 1'b0;

reg scan_equal_hit = 1'b0;
reg scan_not_found = 1'b0;
reg wrong_cylinder = 1'b0;
reg[6:0] cylinder[0:1];
reg[7:0] sector_id = 8'hc1;
reg[7:0] sector_size = 8'h02; // 512 bytes
reg fault_fdd = 1'b0;

wire trk0_fdd[1:0] = {cylinder[1] == 7'd0, cylinder[0] == 7'd0};
reg side_fdd = 1'b0;
reg sideselect_fdd = 1'b0;
reg cm = 1'b0;
reg crc_error = 1'b0;
reg head = 1'b0;

// TODO fake data
reg readerror = 1'b0;
reg disk_error = 1'b0;
reg wp_error = 1'b0;
reg seek_good = 1'b0;

always @(posedge clk) begin
  prev_rd_n <= rd_n;
  prev_wr_n <= wr_n;
  
  // fifo default values
  fifo_out_read <= 1'b0;
  fifo_in_write <= 1'b0;
  fifo_reset <= 0;
  
  // handle chip reset
  if (!rst_n) begin
    disk_sr[31:0] <= 0;
    fifo_reset <= 1;
    fifo_in_size <= 1'b0;
    state <= IDLE;
  end

  if (state == READING && fifo_empty) begin
    state <= IDLE;
    status <= STATUS_RX;
    results_len <= 7;
  end

  if (prev_rd_n && !rd_n && ce) begin
    if (!a0) begin
      dout[7:0] <= {rfm, dio, exm, busy, 2'b00, fdcbusy[1:0]};
    end else if (status == STATUS_EXEC) begin
      if (state == READING) begin
        fifo_out_read <= 1'b1;
        dout[7:0] <= fifo_out_data[7:0];
        last_byte_read <= fifo_empty;

      end else if (recnotfound) begin
        status <= STATUS_RX;
        disk_error <= 1'b1;
        results_len <= 7;
       end

    end else if (status == STATUS_RX) begin
      if (results_pos == results_len) dout[7:0] <= 8'hff;
      else begin
        if (ins[4:0] == SENSE_INT_STATUS) begin
          if (|intstat0) begin 
            intstat0[7:0] <= 8'h00;
            pcn[7:0] <= cylinder[0];
          end else if (|intstat1) begin
            intstat1[7:0] <= 8'h00;
            pcn[7:0] <= cylinder[1];
          end
        end

        case (results_pos)
          8'h00: dout[7:0] <= 
            ins[4:0] == SENSE_INT_STATUS && (|intstat0) ? {intstat0[7:4], not_ready[0], 3'd0} :
            ins[4:0] == SENSE_INT_STATUS && (|intstat1) ? {intstat1[7:4], not_ready[1], 3'd1} :
            (ins[4:0] == SENSE_INT_STATUS || ins[4:0] == INVALID_INS) ? 8'h80 :
            ins[4:0] == SENSE_DRIVE_STATUS && drsel ?
              {1'b0, disk_wp[1], rdy_fdd[1], cylinder[1] == 0 ? 1'b1 : 1'b0, side_fdd, sideselect_fdd, 2'b01} :
            ins[4:0] == SENSE_DRIVE_STATUS ?
              {1'b0, disk_wp[0], rdy_fdd[0], cylinder[0] == 0 ? 1'b1 : 1'b0, side_fdd, sideselect_fdd, 2'b00} :
              {1'b0, disk_error, 1'b0, 1'b0, not_ready[drsel], 2'b00, drsel};
              
          8'h01: dout[7:0] <= 
            ins[4:0] == SENSE_INT_STATUS ? pcn :
            {bad_cylinder, 1'b0, data_error, 1'b0, 1'b0, recnotfound, wp_error, recnotfound};
          8'h02: dout[7:0] <= {1'b0, cm, crc_error, wrong_cylinder, scan_equal_hit, scan_not_found, bad_cylinder, recnotfound};
          8'h03: dout[7:0] <= cylinder[drsel];
          8'h04: dout[7:0] <= disk_cr[15:8];
          8'h05: dout[7:0] <= sector_id[7:0];
          8'h06: dout[7:0] <= sector_size;
        endcase
      end
        
      if ((results_pos + 1) != results_len)
        results_pos <= results_pos + 1;
      else begin
        status <= STATUS_IDLE;
        results_len <= 0;
        params_len <= 0;
        results_pos <= 0;
        params_pos <= 0;
      end
    end else dout[7:0] <= 8'hff;
  end else if (prev_wr_n && !wr_n && motorctl) begin
    motor_on <= din[0];

  end else if (prev_wr_n && !wr_n && ce && a0) begin
    if (status == STATUS_IDLE) begin // receiving command
      params_pos <= 0;
      recnotfound <= 1'b0;
      disk_error <= 1'b0;
      wp_error <= 1'b0;

      status <= STATUS_CMD;
      ins[7:0] <= din[7:0];
      case (din[4:0])
        READ_DATA,READ_DELETED_DATA,WRITE_DATA,WRITE_DELETED_DATA,READ_TRACK,SCAN_EQUAL,SCAN_HEQUAL,SCAN_LEQUAL:
          params_len <= 8;
        FORMAT_TRACK:
          params_len <= 5;
        SEEK, SPECIFY:
          params_len <= 2;
        READ_ID, RECALIBRATE, SENSE_DRIVE_STATUS: begin
          params_len <= 1;
        end
        SENSE_INT_STATUS: begin
          params_len <= 0;
          results_len <= (|{intstat0, intstat1}) ? 2 : 1;
          status <= STATUS_RX;
        end
        default: begin
          params_len <= 0;
          status <= STATUS_RX;
          results_len <= 1;
          ins[7:0] <= INVALID_INS;
        end
      endcase
    
    end else if (status == STATUS_CMD) begin // receiving parameters
      params[params_pos] <= din;
      params_pos <= params_pos + 1;
      
      if (params_pos == 0) drsel <= din[0];

      if (din[0])
        rdy_fdd[1] <= motor_on ? disk_cr[6] : 1'b0;
      else
        rdy_fdd[0] <= motor_on ? disk_cr[5] : 1'b0;

      // received last parameter
      if ((params_pos + 1) == params_len) begin
        results_pos <= 0;
        status <= STATUS_RX;

        if (ins[4:0] == SENSE_DRIVE_STATUS) begin
          results_len <= 1;
          
        end else if (ins[4:0] == SPECIFY) begin
          status <= STATUS_IDLE;
        end else if (ins[4:0] == RECALIBRATE) begin
          state <= SEEKING;
          cylinder[din[0]] <= 8'd0;
          disk_sr[15:0] <= {head, 7'd0, sector_id[7:0]};
          disk_sr[16] <= 1'b0;
          disk_sr[25:24] <= din[0] ? 2'b10 : 2'b01;
          fdcbusy[din[0]] <= 1'b1;
          status <= STATUS_IDLE;
        end else if (ins[4:0] == SEEK) begin
          state <= SEEKING;
          cylinder[drsel] <= din[7:0];
          disk_sr[15:0] <= {head, din[6:0], sector_id[7:0]};
          disk_sr[16] <= 1'b0;
          disk_sr[25:24] <= drsel ? 2'b10 : 2'b01;
          fdcbusy[drsel] <= 1'b1;
          status <= STATUS_IDLE;
        end else if (ins[4:0] == READ_ID) begin
          state <= READID;
          disk_sr[16] <= 1'b0;
          disk_sr[23:22] <= din[0] ? 2'b10 : 2'b01;
          status <= STATUS_EXEC;
          results_len <= 7;
        end else if (ins[4:0] == WRITE_DATA) begin
          if (disk_wp[drsel]) begin
            status <= STATUS_RX;
            results_len <= 7;
            wp_error <= 1'b1;
            disk_error <= 1'b1;
            
          end else begin
            state <= STARTWRITE;
            cylinder[drsel] <= params[1];
            head <= params[2][0];
            sector_id <= params[3];
            fifo_reset <= 1'b1;
            fifo_in_size <= 1'b0;
            status <= STATUS_EXEC;
          end
        end else if (ins[4:0] == READ_DATA || ins[4:0] == READ_DELETED_DATA) begin
          fifo_reset <= 1'b1;
          last_byte_read <= 1'b0;
          state <= READSECT;
          disk_sr[21:0] <= {6'b000, drsel, ~drsel, 1'b0, head, params[1][6:0], params[3][7:0]};

          cylinder[drsel] <= params[1];
          head <= params[2][0];
          sector_id <= params[3];
          status <= STATUS_EXEC;
          results_len <= 7;
          
        end else begin
          results_len <= 7;
        end
      end
    end else if (status == STATUS_EXEC) begin // doing something
      if (ins[4:0] == WRITE_DATA) begin
        fifo_in_write <= 1'b1;
        fifo_in_size <= fifo_in_size + 1;
        if (fifo_in_size == 511) begin
          state <= COMMIT;
          if (drsel)
            disk_sr[21:0] <= {6'b100000, head, cylinder[drsel][6:0], sector_id[7:0]};
          else
            disk_sr[21:0] <= {6'b010000, head, cylinder[drsel][6:0], sector_id[7:0]};
        end
      end
    end
  end
  
    // has finished reading/writing sector, reset read command
  if (disk_cr[4] && state == COMMIT) begin // finished command
    disk_sr[21:20] <= 2'b00; // reset sector write command
    disk_sr[16] <= 1'b1; // signal ack of ack
    recnotfound <= disk_cr[3];
    state <= IDLE;
    status <= STATUS_RX;
    disk_error <= disk_cr[3];
  end
  
  if (disk_cr[4] && state == READID) begin
    disk_sr[23:22] <= 2'b00; // reset command
    disk_sr[16] <= 1'b1; // signal ack of ack
    disk_error <= disk_cr[3];
    sector_id[7:0] <= disk_cr[31:24];
    status <= STATUS_RX;
  end

  if (disk_cr[4] && state == READSECT) begin // finished command
    disk_sr[18:17] <= 2'b00; // reset sector read command
    disk_sr[16] <= 1'b1; // signal ack of ack
    recnotfound <= disk_cr[3];
    disk_error <= disk_cr[3];
    if (disk_cr[3]) begin
      status <= STATUS_RX;
    end

    state <= disk_cr[3] ? IDLE : READING;
  end
  
  if (|disk_cr[1:0] && state == SEEKING) begin // finished seek
    disk_sr[25:24] <= 2'b00; // reset seek
    disk_sr[16] <= 1'b1; // signal ack of ack
    disk_error <= disk_cr[3];
    if (disk_cr[1]) begin
      fdcbusy[1] <= 1'b0;
      intstat1 <= {1'b0, disk_cr[3], ~disk_cr[3], 1'b0, 1'b0, 3'd1};//{2'b11, 1'b0, 1'b0, not_ready, 3'd0}
    end else begin
      fdcbusy[0] <= 1'b0;
      intstat0 <= {1'b0, disk_cr[3], ~disk_cr[3], 1'b0, 1'b0, 3'd0};//{2'b11, 1'b0, 1'b0, not_ready, 3'd0}
    end
    state <= IDLE;
  end

end

//   assign debug[31:0] = disk_cr[31:0];
  assign debug[31:0] = {
    ins[7:0],
    1'b0, cylinder[0][6:0],
//     1'b0, results_pos[2:0],
//     1'b0, results_len[2:0],
    sector_id[7:0],
//     params_pos[3:0],
//     params_len[3:0],
    fifo_empty, motor_on, status[1:0],
    disk_cr[4], state[2:0]};

endmodule
