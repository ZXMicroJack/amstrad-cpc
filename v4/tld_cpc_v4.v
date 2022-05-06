`timescale 1ns / 1ps
`default_nettype none

//////////////////////////////////////////////////////////////////////////////////
// Company: AZXUNO
// Engineer: Miguel Angel Rodriguez Jodar
// 
// Create Date:    19:12:34 03/16/2017 
// Design Name:    
// Module Name:    tld
// Project Name:   The TLD for the Amstrad CPC core
// Target Devices: ZXUNO Spartan 6
// Additional Comments: all rights reserved for now
//
//////////////////////////////////////////////////////////////////////////////////

module tld_cpc (
  input wire clk50mhz,
  output wire [2:0] r,
  output wire [2:0] g,
  output wire [2:0] b,
  output wire hsync,  // hsync en el pineado de la FPGA
  output wire vsync,
  output wire stdn,
  output wire stdnb,
  // Audio y EAR
  input wire ear,
  output wire audio_out_left,
  output wire audio_out_right,
  // Teclado PS/2
  input wire clkps2,
  input wire dataps2,
  // Joystick (de momento, solo un jugador)
  input wire joyup,
  input wire joydown,
  input wire joyleft,
  input wire joyright,
  input wire joyfire1,
  input wire joyfire2,
  // Interface con la SRAM de 512KB
  output wire [20:0] sram_addr,
  inout wire [7:0] sram_data,
  output wire sram_we_n,
  //////// sdcard ////////
  output wire sd_cs_n,
  output wire sd_clk,
  output wire sd_mosi,
  input wire sd_miso
  );

  assign stdn = 1'b0;  // fijar norma PAL
  assign stdnb = 1'b1; // y conectamos reloj PAL

  wire red, red_oe;
  wire green, green_oe;
  wire blue, blue_oe;
  wire hsync_pal, vsync_pal, csync_pal;
  
  wire [2:0] ri = (red_oe)? {red,red,red} : 3'd4;
  wire [2:0] gi = (green_oe)? {green,green,green} : 3'd4;
  wire [2:0] bi = (blue_oe)? {blue,blue,blue} : 3'd4;

  // Reloj principal  
  wire ck16, ck32;
  relojes_cpc master_clocks (
    .CLK_IN1(clk50mhz),
    .CLK_OUT1(ck32),
    .CLK_OUT2(ck16)
  );

  // Power on reset y configuración inicial
  wire master_reset_n;
  wire vga_on, scanlines_on;
  config_retriever (
    .clk(ck16),
    .sram_addr(sram_addr),
    .sram_data(sram_data),
    .sram_we_n(sram_we_n),
    .pwon_reset_n(master_reset_n),
    .vga_on(vga_on),
    .scanlines_on(scanlines_on)
  );
  
  cpc la_maquina (
    .ck16(ck16),
    .pown_reset_n(master_reset_n),
    .red(red),
    .red_oe(red_oe),
    .green(green),
    .green_oe(green_oe),
    .blue(blue),
    .blue_oe(blue_oe),
    .hsync_pal(hsync_pal),
    .vsync_pal(vsync_pal),
    .csync_pal(csync_pal),
    .ear(ear),
    .audio_out_left(audio_out_left),
    .audio_out_right(audio_out_right),
    .clkps2(clkps2),
    .dataps2(dataps2),
    .joyup(joyup),
    .joydown(joydown),
    .joyleft(joyleft),
    .joyright(joyright),
    .joyfire1(joyfire1),
    .joyfire2(joyfire2),
    .sram_addr(sram_addr),
    .sram_data(sram_data),
    .sram_we_n(sram_we_n)
  );

  wire [7:0] riosd;
  wire [7:0] giosd;
  wire [7:0] biosd;

	vga_scandoubler #(.CLKVIDEO(16000)) salida_vga (
		.clkvideo(ck16),
		.clkvga(ck32),
    .enable_scandoubling(vga_on),
    .disable_scaneffect(~scanlines_on),
		.ri(riosd[7:5]),
		.gi(giosd[7:5]),
		.bi(biosd[7:5]),
		.hsync_ext_n(hsync_pal),
		.vsync_ext_n(vsync_pal),
    .csync_ext_n(csync_pal),
		.ro(r),
		.go(g),
		.bo(b),
		.hsync(hsync),
		.vsync(vsync)
   );	 

    wire osd_window;
  wire osd_pixel;
  
//   assign led = sd_cs_n ? 1'b0 : 1'b1;
// TODO
//   always @(posedge clk390k625)
//     led <= sd_cs_n ? 1'b0 : 1'b1;

  wire[7:0] disk_data_in0;
  wire[7:0] disk_data_out0;
  wire[31:0] disk_sr;
  wire[31:0] disk_cr;
  wire disk_data_clkout, disk_data_clkin;
  wire[15:0] dswitch;
  wire host_divert_keyboard;
  wire host_divert_sdcard;

  CtrlModule MyCtrlModule (
//     .clk(clk6),
//     .clk26(clk48),
    .clk(ck16),
    .clk26(ck32),
    .reset_n(1'b1),

    //-- Video signals for OSD
    .vga_hsync(hsync_pal),
    .vga_vsync(vsync_pal),
    .osd_window(osd_window),
    .osd_pixel(osd_pixel),

    //-- PS2 keyboard
    .ps2k_clk_in(clkps2),
    .ps2k_dat_in(dataps2),

    //-- SD card signals
    .spi_clk(sd_clk),
    .spi_mosi(sd_mosi),
    .spi_miso(sd_miso),
    .spi_cs(sd_cs_n),

    //-- DIP switches
    .dipswitches(dswitch),
    
    //-- Control signals
    .host_divert_keyboard(host_divert_keyboard),
    .host_divert_sdcard(host_divert_sdcard),

    // tape interface
//      .ear_in(micout),
//      .ear_out(ear_in_sc),
//     .clk390k625(clk390k625),

     // disk interface
    .disk_data_in(disk_data_out0),
    .disk_data_out(disk_data_in0),
    .disk_data_clkin(disk_data_clkout),
    .disk_data_clkout(disk_data_clkin),

      // disk interface
    .disk_sr(disk_sr),
    .disk_cr(disk_cr)

//       .tape_data_out(tape_data),
//       .tape_dclk_out(tape_dclk),
//       .tape_reset_out(tape_reset),
// 
//       .tape_hreq(tape_hreq),
//       .tape_busy(tape_busy),
//       .cpu_reset(1'b0)
	
   );

   wire[3:0] vga_r_o;
   wire[3:0] vga_g_o;
   wire[3:0] vga_b_o;

   wire[7:0] vga_red_i, vga_green_i, vga_blue_i;

   assign vga_red_i = {ri[2:0], 5'h0};
   assign vga_green_i = {gi[2:0], 5'h0};
   assign vga_blue_i = {bi[2:0], 5'h0};
   
   // OSD Overlay
   OSD_Overlay overlay (
//      .clk(clk48),
     .clk(ck32),
     .red_in(vga_red_i),
     .green_in(vga_green_i),
     .blue_in(vga_blue_i),
     .window_in(1'b1),
     .osd_window_in(osd_window),
     .osd_pixel_in(osd_pixel),
     .hsync_in(hsync_pal),
     .red_out(riosd),
     .green_out(giosd),
     .blue_out(biosd),
     .window_out( ),
     .scanline_ena(1'b0)
   );
   
   
endmodule
