// VGA/HDMI timing controller — 640x480 @ 60 Hz, 25 MHz pixel clock.
// Pixel data is read from an external BRAM via bram_addr / bram_rdata.
// BRAM has 1-cycle registered output latency, so hsync/vsync/dataEnable use
// a 2-stage pipeline to keep them aligned with the BRAM read data.

module PVI(
  input  clock, clock50, reset,
  input  switchR, switchG, switchB,

  output reg  hsync, vsync,
  output reg  dataEnable,
  output reg  vgaClock,
  output [23:0] RGBchannel,

  // BRAM port B interface
  output [18:0] bram_addr,  // read address presented to BRAM each cycle
  input  [7:0]  bram_rdata  // 8-bit grayscale pixel data from BRAM (unregistered output)
);

reg [9:0] pixelH, pixelV;

parameter H_ACTIVE = 640;
parameter H_FP     = 16;
parameter H_SYNC   = 96;
parameter H_TOTAL  = 800;

parameter V_ACTIVE = 480;
parameter V_FP     = 10;
parameter V_SYNC   = 2;
parameter V_TOTAL  = 525;

// 1. Pixel / line counters
always @(posedge clock or posedge reset) begin
  if (reset) begin
    pixelH <= 0;
    pixelV <= 0;
  end 
  else begin
    if (pixelH == H_TOTAL - 1) begin
      pixelH <= 0;
      pixelV <= (pixelV == V_TOTAL - 1) ? 0 : pixelV + 1;
    end 
    else begin
      pixelH <= pixelH + 1;
    end
  end
end

// 2. BRAM read address — combinational from current counter values.
//    BRAM latches this address at the current clock edge and outputs data
//    one cycle later.  The 2-stage sync pipeline below compensates.
assign bram_addr = (pixelV[8:0] << 9) + (pixelV[8:0] << 7) + pixelH;
// = pixelV * 512 + pixelV * 128 + pixelH = pixelV * 640 + pixelH

// 3. Sync / DE pipeline — 1 stage.
//    BRAM output is UNREGISTERED (combinational after address register), so it
//    updates at the same time as these registered signals — both reflect the
//    counter value from before the current clock edge.  1 stage is sufficient.
always @(posedge clock or posedge reset) begin
  if (reset) begin
    hsync      <= 1;
    vsync      <= 1;
    dataEnable <= 0;
  end 
  else begin
    hsync      <= ((pixelH >= H_ACTIVE + H_FP) && (pixelH < H_ACTIVE + H_FP + H_SYNC)) ? 1'b0 : 1'b1;
    vsync      <= ((pixelV >= V_ACTIVE + V_FP) && (pixelV < V_ACTIVE + V_FP + V_SYNC)) ? 1'b0 : 1'b1;
    dataEnable <= (pixelH < H_ACTIVE) && (pixelV < V_ACTIVE);
  end
end

// 4. Pixel clock
always @(*) vgaClock = ~clock;

// 5. Expand 8-bit grayscale to 24-bit RGB (R=G=B)
assign RGBchannel = {bram_rdata, bram_rdata, bram_rdata};

endmodule
