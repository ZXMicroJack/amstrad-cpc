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
  output wire sram_we_n
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

	vga_scandoubler #(.CLKVIDEO(16000)) salida_vga (
		.clkvideo(ck16),
		.clkvga(ck32),
    .enable_scandoubling(vga_on),
    .disable_scaneffect(~scanlines_on),
		.ri(ri),
		.gi(gi),
		.bi(bi),
		.hsync_ext_n(hsync_pal),
		.vsync_ext_n(vsync_pal),
    .csync_ext_n(csync_pal),
		.ro(r),
		.go(g),
		.bo(b),
		.hsync(hsync),
		.vsync(vsync)
   );	 

endmodule
