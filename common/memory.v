`timescale 1ns / 1ps
`default_nettype none

//////////////////////////////////////////////////////////////////////////////////
// Company: AZXUNO
// Engineer: Miguel Angel Rodriguez Jodar
// 
// Create Date:    19:12:34 03/16/2017 
// Design Name:    
// Module Name:    memory
// Project Name:   Memory manager (RAM & ROM) for the Amstrad core
// Target Devices: ZXUNO Spartan 6
// Additional Comments: all rights reserved for now
//
//////////////////////////////////////////////////////////////////////////////////

module memory_cpc464 (
  input wire clk,
  input wire reset_n,
  // Señales desde la CPU
  input wire [15:0] cpu_addr,
  input wire mreq_n,
  input wire iorq_n,
  input wire rd_n,
  input wire wr_n,
  // Señales desde el GA/CRTC
  input wire [15:0] vram_addr,
  input wire ready,
  input wire cpu_n,
  input wire romen_n,
  input wire ramrd_n,
  input wire ras_n,
  input wire cas_n,
  input wire mwe_n,
  input wire en244_n,
  // Buses de datos a CPU y GA
  input wire [7:0] data_from_cpu,
  output reg [7:0] data_to_cpu,  
  output reg memory_oe_n,
  output reg [7:0] data_to_ga,
  // Interface con la SRAM de 512KB
  output wire [20:0] sram_addr,
  inout wire [7:0] sram_data,
  output wire sram_we_n
  );

  // De momento, este manejador va a ser la cosa más simple del mundo, ya que sólo implementaré la página base
  // o sea, la memoria de un CPC 464. Las dos ROMs estarán en BRAM en la FPGA

  // De la CPC Wiki, info técnica sobre cómo mapear las ROMs:
  // The ROM Bank Number is not stored anywhere inside of the CPC. Instead, peripherals must watch the bus for 
  // writes to Port DFxxh, check if the Bank Number matches the Number where they want to map their ROM to, 
  // and memorize the result by setting/clearing a flipflop accordingly (eg. a 74LS74).

  // If the flipflop indicates a match, and the CPC outputs A15=HIGH (upper memory half), then the peripheral 
  // should set /OE=LOW (on its own ROM chip), and output the opposite level, ROMDIS=HIGH to the CPC (disable 
  // the CPC's BASIC ROM).

  // Additionally the CPC's /ROMEN should be wired to peripheral ROM chip's /CS pin. A14 doesn't need to be 
  // decoded since there is no ROM at 8000h..BFFFh, only at C000h..FFFFh.

  // By default, if there are no peripherals issuing ROMDIS=HIGH, then BASIC is mapped to all ROM banks in 
  // range of 00h..FFh. 
  
  wire [7:0] data_from_rom, data_from_ram;
  reg [20:0] dram_addr;
  
  // Instanciamos la ROM, que de momento estará en BRAM
  rom romcpc (
    .clk(clk),
    .a(cpu_addr[14:0]),
    .dout(data_from_rom)
  );

  ram dram (
    .clk(clk),
    .reset_n(reset_n),
    .a(dram_addr),
    .ras_n(ras_n),
    .cas_n(cas_n),
    .we_n(mwe_n),
    .din(data_from_cpu),
    .dout(data_from_ram),
    .sram_addr(sram_addr),
    .sram_data(sram_data),
    .sram_we_n(sram_we_n)
  );

  // Latch LS373 (IC114)
  reg [7:0] latch_data_from_ram;
  always @* begin
    if (ready)
      latch_data_from_ram = data_from_ram;
  end
  
  // Aqui se decide qué cosa ve la CPU, si un dato de ROM o de RAM
  always @* begin
    data_to_cpu = 8'hFF;
    memory_oe_n = 1'b1;
    if (romen_n == 1'b0) begin
      data_to_cpu = data_from_rom;
      memory_oe_n = 1'b0;
    end
    else if (ramrd_n == 1'b0) begin
      data_to_cpu = latch_data_from_ram;
      memory_oe_n = 1'b0;
    end
  end
  
  // Aquí se decide qué cosa ve la RAM, si una dirección de CPU o de la Gate Array
  always @* begin
    if (cpu_n == 1'b0)
      dram_addr = {5'b00000, cpu_addr};
    else
      dram_addr = {5'b00000, vram_addr};
  end
      
  // Aquí se decide cuando se le da el bus de datos a la GA. Es el transceiver IC115
  always @* begin
    if (en244_n == 1'b1)
      data_to_ga = data_from_ram;
    else
      data_to_ga = data_from_cpu;  // rutamos la salida de datos de la CPU a la GA cuando se quiere acceder a ella
  end
endmodule

module rom ( // ROM de 32KB, conteniendo la lower ROM y la upper ROM 0
  input wire clk,
  input wire [14:0] a,
  output reg [7:0] dout
  );

  reg [7:0] mem[0:32767];
  initial begin
    $readmemh ("os464.hex", mem, 16'h0000, 16'h3FFF);
    $readmemh ("basic1-0.hex", mem, 16'h4000, 16'h7FFF);
    //$readmemh ("wiz.hex", mem, 0);
  end
  
  always @(posedge clk)
    dout <= mem[a];
endmodule

module ram (
  input wire clk,
  input wire reset_n,
  input wire [20:0] a,
  input wire ras_n,
  input wire cas_n,
  input wire we_n,
  input wire [7:0] din,
  output reg [7:0] dout,
  // Interface actual con la SRAM
  output tri [20:0] sram_addr,
  inout wire [7:0] sram_data,
  output tri sram_we_n
  );
  
  // Aquí se decide cuándo la SRAM conmuta a bus de entrada o salida, según lo que se haga sea lectura o escritura
  assign sram_data = (sram_we_n == 1'b0)? din : 8'hZZ;
  assign sram_we_n = (reset_n == 1'b0)? 1'bz : ras_n | cas_n | we_n;
  assign sram_addr = (reset_n == 1'b0)? 21'hZZZZZZ : addr;
  
  reg [20:0] addr;
  always @(posedge clk) begin
    if (ras_n == 1'b0)
      addr <= a;
    if (ras_n == 1'b0 && cas_n == 1'b0 && we_n == 1'b1)
      dout <= sram_data;
  end
endmodule  
