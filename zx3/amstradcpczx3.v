`timescale 1ns / 1ps
`default_nettype none
`define DPACTIVE
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

module amstradcpczx3 (
  input wire clk50mhz,
  output wire [7:0] vga_r,
  output wire [7:0] vga_g,
  output wire [7:0] vga_b,
  output wire vga_hs,  // hsync en el pineado de la FPGA
  output wire vga_vs,
  // Audio y EAR
  input wire ear,
  output wire audio_left,
  output wire audio_right,
  // Teclado PS/2
  input wire clkps2,
  input wire dataps2,
  // Joystick (de momento, solo un jugador)
//   input wire joyup,
//   input wire joydown,
//   input wire joyleft,
//   input wire joyright,
//   input wire joyfire1,
//   input wire joyfire2,
  // Interface con la SRAM de 512KB
  output wire [19:0] sram_addr,
  inout wire [7:0] sram_data,
  output wire sram_we_n,
  output wire sram_oe_n,
  output wire sram_ub_n,
  output wire sram_lb_n,
  //////// sdcard ////////
  output wire sd_cs_n,
  output wire sd_clk,
  output wire sd_mosi,
  input wire sd_miso,
  output wire led,
  output wire led2,
  
`ifdef DPACTIVE
  output wire i2s_bclk,
  output wire i2s_lrclk,
  output wire i2s_dout,
  output wire dp_tx_lane_p,
  output wire dp_tx_lane_n,
  input wire  dp_refclk_p,
  input wire  dp_refclk_n,
  input wire  dp_tx_hp_detect,
  inout wire  dp_tx_auxch_tx_p,
  inout wire  dp_tx_auxch_tx_n,
  inout wire  dp_tx_auxch_rx_p,
  inout wire  dp_tx_auxch_rx_n,   
`endif
  input wire joy_data,
  output wire joy_clk,
  output wire joy_load_n
  );

  wire joy1up;
  wire joy1down;
  wire joy1left;
  wire joy1right;
  wire joy1fire1;
  wire joy1fire2;
  wire[8:0] audio_out_left;
  wire[8:0] audio_out_right;

  wire [2:0] r;
  wire [2:0] g;
  wire [2:0] b;
  wire [20:0] sram_addr_tmp;

`ifndef DPACTIVE
  assign vga_r[7:0] = {r[2:0], 5'd0};
  assign vga_g[7:0] = {g[2:0], 5'd0};
  assign vga_b[7:0] = {b[2:0], 5'd0};
`endif
  assign sram_addr[19:0] = sram_addr_tmp[19:0];
  assign sram_oe_n = ~sram_we_n;
//   assign sram_oe_n = (mreq_n == 1'b0 && rd_n == 1'b0) ? 1'b0 : 1'b1;

  assign sram_lb_n = 1'b0;
  assign sram_ub_n = 1'b1;

  
  // ctrl-module signals
  wire host_divert_keyboard;
  wire[7:0] disk_data_in;
  wire[7:0] disk_data_out;
  wire[31:0] disk_sr;
  wire[31:0] disk_cr;
  wire disk_data_clkout, disk_data_clkin;
  wire kbd_mreset;
 
  wire red, red_oe;
  wire green, green_oe;
  wire blue, blue_oe;
  wire hsync_pal, vsync_pal, csync_pal;
  
  wire mono;
  wire [2:0] ri = (red_oe)? {red,red,red} : 3'd4;
  wire [2:0] gi = (green_oe)? {green,green,green} : 3'd4;
  wire [2:0] bi = (blue_oe)? {blue,blue,blue} : 3'd4;

  // Reloj principal  
  wire ck16, ck32, ck50;
  relojes_cpc master_clocks (
    .CLK_IN1(clk50mhz),
    .CLK_OUT1(ck32),
    .CLK_OUT2(ck16),
    .CLK_OUT3(ck50)
  );

  // Power on reset y configuraci�n inicial
//   wire master_reset_n;
//   wire vga_on, scanlines_on;
  wire vga_on = 1'b1, scanlines_on = 1'b0;
//   config_retriever (
//     .clk(ck16),
//     .sram_addr(sram_addr_tmp),
//     .sram_data(sram_data),
//     .sram_we_n(sram_we_n),
//     .pwon_reset_n(master_reset_n),
//     .vga_on(vga_on),
//     .scanlines_on(scanlines_on)
//   );

  
  
// assign sram2_addr[18:0] = rom_initialised ? {1'b0, ram_page[4:0], addr[12:0]} : romwrite_addr[18:0];
// assign sram2_din[7:0] = rom_initialised ? cpu_dout[7:0] : romwrite_data[7:0];
//   
// 	bootloader bootloader_inst(
// 		.clk(sys_clk_i),
// 		.host_bootdata(host_bootdata),
// 		.host_bootdata_ack(host_bootdata_ack),
// 		.host_bootdata_req(host_bootdata_req),
// 		.host_reset(host_reset),
// 		.romwrite_data(romwrite_data),
// 		.romwrite_wr(romwrite_wr),
// 		.romwrite_addr(romwrite_addr),
// 		.rom_initialised(rom_initialised)
// 	);

  wire [31:0] host_bootdata;
  wire host_bootdata_ack;
  wire host_bootdata_req;
  wire host_rom_initialised;
  wire[31:0] debug;
  wire[31:0] debug2;
  wire kbd_scandoubler;
  wire pwon_reset;
  
  cpc la_maquina (
    .ck16(ck16),
    .pown_reset_n(~pwon_reset),
    .red(red),
    .red_oe(red_oe),
    .green(green),
    .green_oe(green_oe),
    .blue(blue),
    .blue_oe(blue_oe),
    .mono(mono),
    .hsync_pal(hsync_pal),
    .vsync_pal(vsync_pal),
    .csync_pal(csync_pal),
    .kbd_scandoubler(kbd_scandoubler),
    .ear(ear),
    .audio_out_left(audio_out_left),
    .audio_out_right(audio_out_right),
    .clkps2(host_divert_keyboard ? 1'b1 : clkps2),
    .dataps2(host_divert_keyboard ? 1'b1 : dataps2),
    .joyup(joy1up),
    .joydown(joy1down),
    .joyleft(joy1left),
    .joyright(joy1right),
    .joyfire1(joy1fire1),
    .joyfire2(joy1fire2),
    .sram_addr(sram_addr_tmp),
    .sram_data(sram_data),
    .sram_we_n(sram_we_n),
    
     // disk interface
    .disk_data_in(disk_data_in),
    .disk_data_out(disk_data_out),
    .disk_data_clkin(disk_data_clkin),
    .disk_data_clkout(disk_data_clkout),

      // disk interface
    .disk_sr(disk_sr),
    .disk_cr(disk_cr),
    .disk_wp(dswitch[7:6]),
    
    // rom loading
		.host_bootdata(host_bootdata),
		.host_bootdata_ack(host_bootdata_ack),
		.host_bootdata_req(host_bootdata_req),
		.host_rom_initialised(host_rom_initialised),
		.kbd_mreset(kbd_mreset)
		//,
		
		// debug
// 		.debug(debug),
// 		.debug2(debug2)
  );
  assign led2 = host_rom_initialised;

  wire [7:0] riosd;
  wire [7:0] giosd;
  wire [7:0] biosd;
  
  reg vga_toggle = 1'b0;
  reg prev_kbd_scandoubler = 1'b0;
  always @(posedge ck50) begin
    prev_kbd_scandoubler <= kbd_scandoubler;
    if (!prev_kbd_scandoubler && kbd_scandoubler)
      vga_toggle <= ~vga_toggle;
  end

`ifndef DPACTIVE
	vga_scandoubler #(.CLKVIDEO(16000)) salida_vga (
		.clkvideo(ck16),
		.clkvga(ck32),
    .enable_scandoubling(vga_on ^ vga_toggle),
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
		.hsync(vga_hs),
		.vsync(vga_vs)
   );	 
`endif

  wire osd_window;
  wire osd_pixel;
  
  assign led = sd_cs_n ? 1'b0 : 1'b1;
// TODO
//   always @(posedge clk390k625)
//     led <= sd_cs_n ? 1'b0 : 1'b1;

  wire[15:0] dswitch;
  wire host_divert_sdcard;

//     always @(posedge clk390k625)
//     assign led = sd_cs_n ? 1'b0 : 1'b1;
//   assign led = mono;
  CtrlModule#(.USE_UART(0), .USE_TAPE(0), .ROMSIZE_BITS(13)) MyCtrlModule (
//     .clk(clk6),
//     .clk26(clk48),
    .clk(ck16),
    .clk26(ck50),
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
    .disk_data_in(disk_data_out),
    .disk_data_out(disk_data_in),
    .disk_data_clkin(disk_data_clkout),
    .disk_data_clkout(disk_data_clkin),

      // disk interface
    .disk_sr(disk_sr),
    .disk_cr(disk_cr),

    // rom loading
		.host_bootdata(host_bootdata),
		.host_bootdata_ack(host_bootdata_ack),
		.host_bootdata_req(host_bootdata_req),
		.host_rom_initialised(host_rom_initialised)
		//,
    
	// from/to ctrl-module

//       .tape_data_out(tape_data),
//       .tape_dclk_out(tape_dclk),
//       .tape_reset_out(tape_reset),
// 
//       .tape_hreq(tape_hreq),
//       .tape_busy(tape_busy),
//       .cpu_reset(1'b0)
		// debug
// 		.debug(debug),
// 		.debug2(debug2)
	
   );

   wire[3:0] vga_r_o;
   wire[3:0] vga_g_o;
   wire[3:0] vga_b_o;

   wire[7:0] vga_red_i, vga_green_i, vga_blue_i;

`ifndef DPACTIVE
   wire[2:0] ri2;
   wire[2:0] gi2;
   wire[2:0] bi2;
   greenscreen greenscreen_inst(
      .ri(ri[2:0]),
      .gi(gi[2:0]),
      .bi(bi[2:0]),
      .ro(ri2[2:0]),
      .go(gi2[2:0]),
      .bo(bi2[2:0]),
      .mono(mono)
   );
`endif

`ifndef DPACTIVE
   assign vga_red_i = {ri2[2:0], 5'h0};
   assign vga_green_i = {gi2[2:0], 5'h0};
   assign vga_blue_i = {bi2[2:0], 5'h0};
`else
   assign vga_red_i = {ri[2:0], 5'h0};
   assign vga_green_i = {gi[2:0], 5'h0};
   assign vga_blue_i = {bi[2:0], 5'h0};
`endif
   // OSD Overlay
   OSD_Overlay overlay (
//      .clk(clk48),
     .clk(ck50),
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

  
//   zxtres_wrapper #(.CLKVIDEO(16)) cosas_del_zxtres (
//   .clkvideo(ck16),                      // reloj de pixel de la se�al de video original (generada por el core)


`ifdef DPACTIVE
  zxtres_wrapper #(.CLKVIDEO(16), .HSTART(207), .VSTART(46)) cosas_del_zxtres (
  .clkvideo(ck16),                      // reloj de pixel de la se�al de video original (generada por el core)
  .enclkvideo(1'b1),                   // si el reloj anterior es mayor que el reloj de pixel, y se necesita un clock enable
  .clkpalntsc(1'b0),                // Reloj de 100 MHz para la generacion del reloj de color PAL o NTSC
  .reset_n(1'b1),                   // Reset de todo el m�dulo
  .reboot_fpga(~kbd_mreset),
  .poweron_reset(pwon_reset), ///////////////////////////////////////////////////////////////////////////////////////////////////////////
  .video_output_sel(vga_on ^ vga_toggle),          // 0: RGB 15kHz + DP   1: VGA + DP
  .disable_scanlines(~scanlines_on),  // 0: emular scanlines (cuidado con el polic�a del retro!)  1: sin scanlines
  .monochrome_sel(mono ? 2'd1 : 2'd0),   // 0 : RGB, 1: f�sforo verde, 2: f�sforo �mbar, 3: escala de grises
//   .interlace_mode(interlace_mode),
//   .field(campo_imagen),
//   .interlaced_image(interlaced_image),
//   .ad724_modo(color_mode),                // Modo de video para el reloj de color. 0 : PAL, 1: NTSC
//   .ad724_clken(enable_gencolorclk),       // Habilita el uso del generador interno de CLK de color

//   .disable_scaneffect(~scanlines_on),
// 		.ri(riosd[7:5]),
// 		.gi(giosd[7:5]),
// 		.bi(biosd[7:5]),
// 		.hsync_ext_n(hsync_pal),
// 		.vsync_ext_n(vsync_pal),
//     .csync_ext_n(csync_pal),
// 		.ro(r),
// 		.go(g),
// 		.bo(b),
// 		.hsync(hsync),
// 		.vsync(vsync)

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
//   .ri({ri[2:0],5'd0}),            // RGB de 24 bits aunque  
//   .gi({gi[2:0],5'd0}),            // despu�s haya que guardar 
//   .bi({bi[2:0],5'd0}),            // menos bits (dep. de la BRAM usada)
  .ri(riosd[7:0]),
  .gi(giosd[7:0]),
  .bi(biosd[7:0]),
//   .ri({riosd[7:5],5'd0}),
//   .gi({giosd[7:5],5'd0}),
//   .bi({biosd[7:5],5'd0}),
  .hsync_ext_n(hsync_pal),  // Sincronismo horizontal y vertical separados. Los necesito separados para poder, dentro del m�dulo
  .vsync_ext_n(vsync_pal),  // medir cu�ndo comienza y termina un scan y un frame, y as� centrar la imagen en el framebuffer
  .csync_ext_n(csync_pal),  // entrada de sincronismo compuesto de la se�al original
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
//   .ula_mode(ula_mode),     // Se�ales espec�ficas para el uso de este
//   .ula_hcont(ula_hcont),   // core de ZX Spectrum. Estas se�ales son las
//   .ula_vcont(ula_vcont),   // que sincronizan la ULA con el framescaler
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////    
  .audio_l({audio_out_left[8:0], 7'd0}),
  .audio_r({audio_out_right[8:0], 7'd0}),
  .i2s_bclk(i2s_bclk),
  .i2s_lrclk(i2s_lrclk),
  .i2s_dout(i2s_dout),
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .ro(vga_r),         // Salida RGB de VGA 
  .go(vga_g),         // o de 15 kHz, seg�n el valor
  .bo(vga_b),         // de video_output_sel
  .hsync(vga_hs),     // Para RGB 15 kHz, aqui estar� el sincronismo compuesto
  .vsync(vga_vs),     // Para RGB 15 kHz, de momento se queda al valor 1, pero aqu� luego ir� el reloj de color x4
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .sd_audio_l(audio_left),
  .sd_audio_r(audio_right),
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .joy_data(joy_data),
  .joy_latch_megadrive(1'b1),
  .joy_clk(joy_clk),
  .joy_load_n(joy_load_n),
  .joy1up(joy1up),
  .joy1down(joy1down),
  .joy1left(joy1left),
  .joy1right(joy1right),
  .joy1fire1(joy1fire1),
  .joy1fire2(joy1fire2),
//   .joy1fire3(joy1fire3),
  .joy1start(),
//   .joy2up(joy2up),
//   .joy2down(joy2down),
//   .joy2left(joy2left),
//   .joy2right(joy2right),
//   .joy2fire1(joy2fire1),
//   .joy2fire2(joy2fire2),
//   .joy2fire3(),
//   .joy2start(),    
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .dp_tx_lane_p(dp_tx_lane_p),          // De los dos lanes de la Artix 7, solo uso uno.
  .dp_tx_lane_n(dp_tx_lane_n),          // Cada lane es una se�al diferencial. Esta es la parte negativa.
  .dp_refclk_p(dp_refclk_p),            // Reloj de referencia para los GPT. Siempre es de 135 MHz
  .dp_refclk_n(dp_refclk_n),            // El reloj tambi�n es una se�al diferencial.
  .dp_tx_hp_detect(dp_tx_hp_detect),    // Indica que se ha conectado un monitor DP. Arranca todo el proceso de entrenamiento
  .dp_tx_auxch_tx_p(dp_tx_auxch_tx_p),  // Se�al LVDS de salida (transmisi�n)
  .dp_tx_auxch_tx_n(dp_tx_auxch_tx_n),  // del canal AUX. En alta impedancia durante la recepci�n
  .dp_tx_auxch_rx_p(dp_tx_auxch_rx_p),  // Se�al LVDS de entrada (recepci�n)
  .dp_tx_auxch_rx_n(dp_tx_auxch_rx_n),   // del canal AUX. Siempre en alta impedancia ya que por aqu� no se transmite nada.
  /////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .dp_ready(),
  .dp_heartbeat()
  );
`endif

endmodule

`ifndef DPACTIVE
module greenscreen(
      input wire[2:0] ri,
      input wire[2:0] gi,
      input wire[2:0] bi,
      output wire[2:0] ro,
      output wire[2:0] go,
      output wire[2:0] bo,
      input wire mono);

  reg[2:0] r;
  reg[2:0] g;
  reg[2:0] b;
  
  assign go = mono ? r + g + b : gi;
  assign ro = mono ? {1'b0, g[2:1]} : ri;
  assign bo = mono ? {2'b00, g[2]} : bi;
  
  
  always @* begin  // a LUT
        case (ri[2:0])  
            3'd0 : r[2:0] = 3'd0;
            3'd1 : r[2:0] = 3'd0;
            3'd2 : r[2:0] = 3'd1;
            3'd3 : r[2:0] = 3'd1;
            3'd4 : r[2:0] = 3'd1;
            3'd5 : r[2:0] = 3'd1;
            3'd6 : r[2:0] = 3'd2;
            3'd7 : r[2:0] = 3'd2;
            default: r[2:0] = 3'd0;
        endcase
    end
    
    always @* begin  // a LUT
        case (gi[2:0])
            3'd0 : g[2:0] = 3'd0;
            3'd1 : g[2:0] = 3'd1;
            3'd2 : g[2:0] = 3'd1;
            3'd3 : g[2:0] = 3'd2;
            3'd4 : g[2:0] = 3'd2;
            3'd5 : g[2:0] = 3'd3;
            3'd6 : g[2:0] = 3'd4;
            3'd7 : g[2:0] = 3'd4;
            default: g[2:0] = 3'd0;
        endcase
    end
    
    always @* begin  // a LUT
        case (bi[2:0])
            3'd0 : b[2:0] = 3'd0;
            3'd1 : b[2:0] = 3'd0;
            3'd2 : b[2:0] = 3'd0;
            3'd3 : b[2:0] = 3'd0;
            3'd4 : b[2:0] = 3'd0;
            3'd5 : b[2:0] = 3'd1;
            3'd6 : b[2:0] = 3'd1;
            3'd7 : b[2:0] = 3'd1;
            default: b[2:0] = 3'd0;
        endcase
    end

endmodule
`endif
