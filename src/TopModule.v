`include "adv7513/adv7513.v"
`include "pixel_gen.v"

// Top-level module.
// IP cores (pll_25, bram_2port) are added via their .qip files.
// Hierarchy:
//   TopModule
//   ├── pll_25       — 50 MHz → 25.175 MHz pixel clock (Quartus IP, not included)
//   ├── pixel_gen    — writes checkerboard pattern to BRAM port A (clock50)
//   ├── bram_2port   — dual-port RAM (Quartus IP, not included)
//   │     port A: write ← pixel_gen  (clock50)
//   │     port B: read  → adv7513    (clock25)
//   └── adv7513      — HDMI output + I2C config
//         └── vgaHdmi — reads BRAM port B and drives HDMI timing
module TopModule(
  input  clock50, reset_n,
  input  switchR, switchG, switchB,

  // AUDIO (unused)
  output HDMI_I2S0,
  output HDMI_MCLK,
  output HDMI_LRCLK,
  output HDMI_SCLK,

  // VIDEO
  output [23:0] HDMI_TX_D,
  output HDMI_TX_VS,
  output HDMI_TX_HS,
  output HDMI_TX_DE,
  output HDMI_TX_CLK,

  // HDMI config
  input  HDMI_TX_INT,
  inout  HDMI_I2C_SDA,
  output HDMI_I2C_SCL,
  output READY,
  output locked
);

wire clock25;
wire reset;
assign reset = ~reset_n;

// BRAM port A signals (pixel_gen → BRAM write, clock50)
wire [18:0] bram_addr_a;
wire [7:0]  bram_wdata_a;
wire        bram_we_a;

// BRAM port B signals (PVI → BRAM read, clock25)
wire [18:0] bram_addr_b;
wire [7:0]  bram_rdata_b;

// Clock generation (50 MHz → 25.175 MHz)
pll_25 pll_25 (
  .refclk   (clock50),
  .rst      (reset),
  .outclk_0 (clock25),
  .locked   (locked)
);

// Checkerboard pattern writer
pixel_gen pixel_gen (
  .clock      (clock50),
  .reset      (~locked),
  .bram_addr  (bram_addr_a),
  .bram_wdata (bram_wdata_a),
  .bram_we    (bram_we_a),
  .done       ()
);

// Dual-port BRAM (Quartus IP: RAM 2-Port, 24-bit × 307200)
// Port A: write-only (clock50) — pixel_gen
// Port B: read-only  (clock25) — vgaHdmi, with registered output
// NOTE: port names must match the IP wizard output.
bram_2port bram_2port (
  .clock_a   (clock50),
  .address_a (bram_addr_a),
  .data_a    (bram_wdata_a),
  .wren_a    (bram_we_a),
  .q_a       (),

  .clock_b   (clock25),
  .address_b (bram_addr_b),
  .data_b    (8'h00),
  .wren_b    (1'b0),
  .q_b       (bram_rdata_b)
);

// ADV7513 HDMI block (video timing + I2C configuration)
adv7513 adv7513 (
  .clock50      (clock50),
  .reset_n      (reset_n),
  .clock25      (clock25),
  .locked       (locked),
  .switchR      (switchR),
  .switchG      (switchG),
  .switchB      (switchB),
  .HDMI_I2S0    (HDMI_I2S0),
  .HDMI_MCLK    (HDMI_MCLK),
  .HDMI_LRCLK   (HDMI_LRCLK),
  .HDMI_SCLK    (HDMI_SCLK),
  .HDMI_TX_D    (HDMI_TX_D),
  .HDMI_TX_VS   (HDMI_TX_VS),
  .HDMI_TX_HS   (HDMI_TX_HS),
  .HDMI_TX_DE   (HDMI_TX_DE),
  .HDMI_TX_CLK  (HDMI_TX_CLK),
  .HDMI_TX_INT  (HDMI_TX_INT),
  .HDMI_I2C_SDA (HDMI_I2C_SDA),
  .HDMI_I2C_SCL (HDMI_I2C_SCL),
  .READY        (READY),
  .bram_addr    (bram_addr_b),
  .bram_rdata   (bram_rdata_b)
);

endmodule
