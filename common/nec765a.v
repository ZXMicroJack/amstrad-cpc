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

//wd1770 regs
  reg recnotfound = 0;
  reg drsel = 0;

  // ctrl-module transfer state machine
  localparam IDLE = 0;
  localparam READSECT = 1;
  localparam READING = 2;
  localparam WRITING = 3;
  localparam COMMIT = 4;
  localparam WAITEND = 5;
  localparam STARTREAD = 6;
  localparam STARTWRITE = 7;
  reg[2:0] state = IDLE;
  
  fifo #(.RAM_SIZE(512), .ADDRESS_WIDTH(9)) fifo_in(
    .q(fifo_out_data),
    .d(disk_data_in),
    .clk(clk),
    .write(disk_data_clkin),
    .read(fifo_out_read),
    .reset(fifo_reset),
    .empty(fifo_empty));

  reg fifo_in_write = 1'b0;
  reg[7:0] fifo_in_data = 8'h00;
  reg writing_sector = 1'b0;
  reg sector_commit = 1'b0;

  reg[9:0] fifo_in_size = 1'b0;
  reg prev_dsr4 = 1'b0;
  wire fifo_out_empty;
  reg drq = 1'b0;
//   reg spin_disk = 1'b0;
  reg index = 1'b0;


  fifo #(.RAM_SIZE(512), .ADDRESS_WIDTH(9)) fifo_out(
    .q(disk_data_out),
    .d(fifo_in_data),
    .clk(clk),
    .write(fifo_in_write),
    .read(disk_data_clkout),
    .reset(fifo_reset),
    .empty(fifo_out_empty));




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

localparam STATUS_IDLE = 0;
localparam STATUS_CMD = 1;
localparam STATUS_EXEC = 2;
localparam STATUS_RX = 3;

reg fdselect = 1'b0;
reg[1:0] status = STATUS_IDLE;

reg[7:0] results[0:7];
reg[2:0] results_len = 0;
reg[2:0] results_pos = 0;

reg[7:0] params[0:10];
reg[3:0] params_len = 0;
reg[3:0] params_pos = 0;

wire rfm = status == STATUS_IDLE || 
  (status == STATUS_EXEC && state == READING && !fifo_empty) ||
  (status == STATUS_RX && results_len != results_pos)
  || (status == STATUS_CMD && params_len != params_pos);
wire dio = status == STATUS_RX || status == STATUS_EXEC;
wire exm = status == STATUS_EXEC;
wire busy = status != STATUS_IDLE;
wire fdcbusy0 = status != STATUS_IDLE && !fdselect;
wire fdcbusy1 = status != STATUS_IDLE && fdselect;
// {rfm, dio, exm, busy, 2'b00, fdcbusy1, fdcbusy0};

reg[7:0] ins;

reg not_ready = 1'b0;
reg bad_cylinder = 1'b0;
reg data_error = 1'b0;
// reg no_sector = 1'b0;
wire no_sector = recnotfound;
// reg no_addr_mark = 1'b0;
wire no_addr_mark = recnotfound;

reg scan_equal_hit = 1'b0;
reg scan_not_found = 1'b0;
reg wrong_cylinder = 1'b0;
reg[6:0] cylinder = 7'h00;
reg[7:0] sector_id = 8'h00;
reg[7:0] sector_size = 8'h02; // 512 bytes
reg[7:0] sto = 8'h00;
reg[7:0] pcn = 8'h00;
reg fault_fdd = 1'b0;

reg rdy_fdd = 1'b0;
reg trk0_fdd = 1'b0;
reg side_fdd = 1'b0;
reg sideselect_fdd = 1'b0;
reg cm = 1'b0;
reg crc_error = 1'b0;
reg head = 1'b0;

// TODO fake data
reg[8:0] datalen = 0;

reg readerror = 1'b0;

always @(posedge clk) begin
  prev_rd_n <= rd_n;
  prev_wr_n <= wr_n;
  
  // fifo default values
  fifo_out_read <= 1'b0;
  
  // handle chip reset
  if (!rst_n) begin
    drq <= 1'b0;
    disk_sr[31:0] <= 0;
    fifo_reset <= 1;
    fifo_in_size <= 1'b0;
    state <= IDLE;
  end else fifo_reset <= 0;

  if (prev_rd_n && !rd_n && ce) begin
    if (!a0) begin 
      dout[7:0] <= {rfm, dio, exm, busy, 2'b00, fdcbusy1, fdcbusy0};
    end else if (status == STATUS_EXEC) begin
      if (state == READING && !fifo_empty) begin
        fifo_out_read <= 1'b1;
        dout[7:0] <= fifo_out_data[7:0];
        if (datalen == 511) begin
          status <= STATUS_RX;
          results_len <= 7;
          results[0] <= {2'b00,1'b1, 1'b0, not_ready, params[0][2:0]};
          results[1] <= {bad_cylinder, 0, data_error, 1'b0, 1'b0, no_sector, disk_wp[params[0][0]], no_addr_mark};
          results[2] <= {0, cm, crc_error, wrong_cylinder, scan_equal_hit, scan_not_found, bad_cylinder, no_addr_mark};
          results[3] <= cylinder;
          results[4] <= head;
          results[5] <= sector_id;
          results[6] <= sector_size;
        end
        datalen <= datalen + 1;
      end else if (recnotfound) begin
//         no_sector <= 1'b1;
        status <= STATUS_RX;
        results_len <= 7;
        results[0] <= {2'b00,1'b1, 1'b0, not_ready, params[0][2:0]};
        results[1] <= {bad_cylinder, 0, data_error, 1'b0, 1'b0, no_sector, disk_wp[params[0][0]], no_addr_mark};
        results[2] <= {0, cm, crc_error, wrong_cylinder, scan_equal_hit, scan_not_found, bad_cylinder, no_addr_mark};
        results[3] <= cylinder;
        results[4] <= head;
        results[5] <= sector_id;
        results[6] <= sector_size;
       end

    end else if (status == STATUS_RX) begin
      dout[7:0] <= results_pos != results_len ? results[results_pos] : 8'hff;
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
  end else if (prev_wr_n && !wr_n && ce && a0) begin
    if (status == STATUS_IDLE) begin // receiving command
      params_pos <= 0;
//       no_sector <= 1'b0;
      recnotfound <= 1'b0;
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
          results_len <= 2;
          results[0] <= {2'b00,1'b1, 1'b0, not_ready, params[0][2:0]};
          results[1] <= pcn;
          status <= STATUS_RX;
        end
        default: begin
          params_len <= 0;
          status <= STATUS_RX;
          results_len <= 1;
          results[0] <= 8'h80;
        end
      endcase
    
    end else if (status == STATUS_CMD) begin // receiving parameters
      params[params_pos] <= din;
      params_pos <= params_pos + 1;
      if ((params_pos + 1) == params_len) begin
        results_pos <= 0;
        status <= STATUS_RX;
        if (ins[4:0] == SENSE_DRIVE_STATUS) begin
          results_len <= 1;
          results[0] <= {fault_fdd, disk_wp[0], rdy_fdd, trk0_fdd, side_fdd, sideselect_fdd, params[0][1:0]};
        end else if (ins[4:0] == SEEK || ins[4:0] == SPECIFY || ins[4:0] == RECALIBRATE) begin
          status <= STATUS_IDLE;
        end else if (ins[4:0] == READ_ID) begin
          results_len <= 7;
          results[0] <= {2'b00,1'b1, 1'b0, not_ready, params[0][2:0]};
          results[1] <= {bad_cylinder, 0, data_error, 1'b0, 1'b0, no_sector, disk_wp[params[0][0]], no_addr_mark};
          results[2] <= {0, cm, crc_error, wrong_cylinder, scan_equal_hit, scan_not_found, bad_cylinder, no_addr_mark};
          results[3] <= cylinder;
          results[4] <= head;
          results[5] <= 8'hc1;
          results[6] <= sector_size;
        end else if (ins[4:0] == READ_DATA) begin
          state <= STARTREAD;

          cylinder <= params[1];
          head <= params[2][0];
          sector_id <= params[3];

          datalen <= 0;
          
          //1c,2h,3r
          
          status <= STATUS_EXEC;
          
        end else begin
          results_len <= 7;
          // {ic[1:0],seek_end, no_track0_equipment_fail, not_ready, hd_at_int, us[1:0]};
          // ic = 01 (failed) 10 (invalid command) 00 (success)
          // hd_at_int = always 0
          // bad cylinder
          results[0] <= {2'b00,1'b1, 1'b0, not_ready, params[0][2:0]};
          results[1] <= {bad_cylinder, 0, data_error, 1'b0, 1'b0, no_sector, disk_wp[params[0][0]], no_addr_mark};
          results[2] <= {0, cm, crc_error, wrong_cylinder, scan_equal_hit, scan_not_found, bad_cylinder, no_addr_mark};
          results[3] <= cylinder;
          results[4] <= head;
          results[5] <= sector_id;
          results[6] <= sector_size;
        end
      end
    end else if (status == STATUS_EXEC) begin // doing something
    end else if (status == STATUS_RX) begin // doing something
//       dout <= (results_pos + 1) < results_len ? results[results_pos] : 8'hff;
//       if ((results_pos + 1) == results_len) status <= STATUS_IDLE;
    end
  end
  
    // has finished reading/writing sector, reset read command
  if (disk_cr[4] && state == COMMIT) begin // finished command
    disk_sr[20] <= 1'b0; // reset sector write command
    disk_sr[21] <= 1'b0; // reset sector write command
    disk_sr[16] <= 1'b1; // signal ack of ack
    recnotfound <= disk_cr[3];
    state <= disk_cr[3] ? IDLE : WAITEND;
  end

  if (disk_cr[4] && state == READSECT) begin // finished command
    disk_sr[17] <= 1'b0; // reset sector read command
    disk_sr[18] <= 1'b0; // reset sector read command
    disk_sr[16] <= 1'b1; // signal ack of ack
    recnotfound <= disk_cr[3];
    if (disk_cr[3]) begin
//       no_sector <= 1'b1;
      status <= STATUS_RX;
      
      results_len <= 7;
      results[0] <= {2'b00,1'b1, 1'b0, not_ready, params[0][2:0]};
      results[1] <= {bad_cylinder, 0, data_error, 1'b0, 1'b0, 1'b1/*no_sector*/, disk_wp[params[0][0]], 1'b1/*no_addr_mark*/};
      results[2] <= {0, cm, crc_error, wrong_cylinder, scan_equal_hit, scan_not_found, bad_cylinder, 1'b1/*no_addr_mark*/};
      results[3] <= cylinder;
      results[4] <= head;
      results[5] <= sector_id;
      results[6] <= sector_size;
    end

    state <= disk_cr[3] ? IDLE : READING;
  end

  if (state == STARTREAD) begin
    state <= READSECT;
    fifo_reset <= 1'b1;
    if (drsel)
      disk_sr[21:0] <= {6'b000100, head, cylinder[6:0], sector_id[7:0]};
    else
      disk_sr[21:0] <= {6'b000010, head, cylinder[6:0], sector_id[7:0]};
  end

  if (state == STARTWRITE) begin
    state <= WRITING;
    fifo_reset <= 1'b1;
    fifo_in_size <= 1'b0;
  end
  
end

//   assign debug[31:0] = disk_cr[31:0];
  assign debug[31:0] = {
    ins[7:0],
    1'b0, results_pos[2:0],
    1'b0, results_len[2:0],
    params_pos[3:0],
    params_len[3:0],
    fifo_empty, 1'b0, status[1:0],
    disk_cr[4], state[2:0]};

endmodule
