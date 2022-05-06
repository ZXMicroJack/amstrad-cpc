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
  output wire sram_we_n,
  input wire[2:0] ram_bank
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

// -- cpcWiki
// -- http://www.cpcwiki.eu/index.php/Gate_Array
// -- -Address-     0      1      2      3      4      5      6      7
// -- 0000-3FFF   RAM_0  RAM_0  RAM_4  RAM_0  RAM_0  RAM_0  RAM_0  RAM_0
// -- 4000-7FFF   RAM_1  RAM_1  RAM_5  RAM_3  RAM_4  RAM_5  RAM_6  RAM_7
// -- 8000-BFFF   RAM_2  RAM_2  RAM_6  RAM_2  RAM_2  RAM_2  RAM_2  RAM_2
// -- C000-FFFF   RAM_3  RAM_7  RAM_7  RAM_7  RAM_3  RAM_3  RAM_3  RAM_3
// --http://www.grimware.org/doku.php/documentations/devices/gatearray
  
  // 128 paging
  // TODO clean up
  reg[3:0] ram_page;
  always @* begin
    casez ({cpu_addr[15:14], ram_bank[2:0]})
      5'b??000: ram_page = {2'b00, cpu_addr[15:14]}; // ram_bank 0
      5'b??010: ram_page = {2'b01, cpu_addr[15:14]}; // ram_bank 2
      5'b0?001: ram_page = {2'b00, cpu_addr[15:14]}; // ram_bank 1
      5'b11001: ram_page = 4'b0111; // ram_bank 1

      5'b00011: ram_page = 4'b0000; // ram_bank 3-0
      5'b01011: ram_page = 4'b0011; // ram_bank 3-1
      5'b10011: ram_page = 4'b0010; // ram_bank 3-2
      5'b11011: ram_page = 4'b0111; // ram_bank 3-3

      5'b00100: ram_page = 4'b0000; // ram_bank 4-0
      5'b01100: ram_page = 4'b0100; // ram_bank 4-1
      5'b1?100: ram_page = {3'b001, cpu_addr[14]}; // ram_bank 4-2/3

      5'b00101: ram_page = 4'b0000; // ram_bank 5-0
      5'b01101: ram_page = 4'b0101; // ram_bank 5-1
      5'b1?101: ram_page = {3'b001, cpu_addr[14]}; // ram_bank 5-2/3

      5'b00110: ram_page = 4'b0000; // ram_bank 6-0
      5'b01110: ram_page = 4'b0110; // ram_bank 6-1
      5'b1?110: ram_page = {3'b001, cpu_addr[14]}; // ram_bank 6-2/3

      5'b00111: ram_page = 4'b0000; // ram_bank 7-0
      5'b01111: ram_page = 4'b0111; // ram_bank 7-1
      5'b1?111: ram_page = {3'b001, cpu_addr[14]}; // ram_bank 7-2/3
    endcase
  end

  // Aquí se decide qué cosa ve la RAM, si una dirección de CPU o de la Gate Array
  always @* begin
    if (cpu_n == 1'b0)
//       dram_addr = {5'b00000, cpu_addr};
      dram_addr = {3'b000, ram_page[3:0], cpu_addr[13:0]};
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
//     $readmemh ("os464.hex", mem, 16'h0000, 16'h3FFF);
//     $readmemh ("basic1-0.hex", mem, 16'h4000, 16'h7FFF);
    //$readmemh ("wiz.hex", mem, 0);

// CPC4128
    $readmemh ("os6128.hex", mem, 16'h0000, 16'h3FFF);
    $readmemh ("basic1-1.hex", mem, 16'h4000, 16'h7FFF);

//  Diagnostics
//     $readmemh ("AmstradDiagLower.rom.hex",  mem, 16'h0000, 16'h3FFF);
//     $readmemh ("AmstradDiagUpper.rom.hex", mem, 16'h4000, 16'h7FFF);
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
