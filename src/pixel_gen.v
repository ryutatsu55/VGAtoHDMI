// Continuous 60 fps frame writer.
// Renders a bouncing ball (Manhattan-distance gradient) onto BRAM port A.
// Black background; ball center is brightest (8'hFF) and fades linearly to 0
// at radius BALL_R.  Ball bounces off screen edges.
//
// Frame timing at clock=50 MHz:
//   Write phase : VGA_W * VGA_H = 307 200 cycles (~6.1 ms)
//   Wait phase  : 526 133 cycles (~10.5 ms)
//   Total       : 833 333 cycles = 1/60 s
//
// Address mapping (matches PVI.v):
//   addr = pixelV * 640 + pixelH  = (pixelV<<9) + (pixelV<<7) + pixelH

module pixel_gen(
  input  clock,   // 50 MHz
  input  reset,   // active-high until PLL locks

  output reg [18:0] bram_addr,
  output reg [7:0]  bram_wdata,
  output reg        bram_we,
  output reg        done      // unused in continuous mode; stays 0
);

// ---- parameters -------------------------------------------------------
parameter VGA_W  = 640;
parameter VGA_H  = 480;
parameter BALL_R = 48;   // ball radius in Manhattan-distance pixels
parameter VEL_X  = 3;   // horizontal speed (pixels per frame)
parameter VEL_Y  = 2;   // vertical speed   (pixels per frame)

// Wait cycles = 833 333 - 307 200 = 526 133
// Wait cycles = 1 666 666 - 307 200 = 1 359 466 for 30fps
parameter WAIT_N = 1359466;

// ---- ball state -------------------------------------------------------
reg [9:0] ball_x, ball_y;
reg       dir_x,  dir_y;   // 0 = moving positive, 1 = moving negative

// ---- write-phase counters ---------------------------------------------
reg [9:0]  pixelH, pixelV;

// ---- frame timer ------------------------------------------------------
reg [20:0] wait_cnt;  // 21-bit: max 2 097 151 > WAIT_N (1 359 466)

// ---- state machine ----------------------------------------------------
localparam ST_WRITE  = 2'd0;
localparam ST_UPDATE = 2'd1;
localparam ST_WAIT   = 2'd2;
reg [1:0] state;

// ---- brightness computation (combinational) ---------------------------
wire [10:0] dx   = (pixelH >= ball_x) ? (pixelH - ball_x) : (ball_x - pixelH);
wire [10:0] dy   = (pixelV >= ball_y) ? (pixelV - ball_y) : (ball_y - pixelV);
wire [11:0] dist = dx + dy;

// Linear falloff: brightness = (BALL_R - dist) * 5  (range 0..240, fits in 8 bits)
wire [7:0] pix = (dist < BALL_R) ? ((BALL_R - dist[6:0]) * 5) : 8'h00;

// -----------------------------------------------------------------------
always @(posedge clock or posedge reset) begin
  if (reset) begin
    ball_x     <= 10'd320;
    ball_y     <= 10'd240;
    dir_x      <= 1'b0;
    dir_y      <= 1'b0;
    pixelH     <= 0;
    pixelV     <= 0;
    wait_cnt   <= 0;
    bram_addr  <= 0;
    bram_wdata <= 0;
    bram_we    <= 0;
    done       <= 0;
    state      <= ST_WRITE;
  end 
  else begin
    case (state)

      // ---- ST_WRITE: scan all pixels, write brightness to BRAM --------
      ST_WRITE: begin
        bram_addr  <= ({10'b0, pixelV} << 9) + ({10'b0, pixelV} << 7) + pixelH;
        bram_wdata <= pix;
        bram_we    <= 1;

        if (pixelH == VGA_W - 1) begin
          pixelH <= 0;
          if (pixelV == VGA_H - 1) begin
            pixelV  <= 0;
            bram_we <= 0;
            state   <= ST_UPDATE;
          end 
          else begin
            pixelV <= pixelV + 1;
          end
        end 
        else begin
          pixelH <= pixelH + 1;
        end
      end

      // ---- ST_UPDATE: move ball, bounce off walls ----------------------
      ST_UPDATE: begin
        bram_we <= 0;

        if (!dir_x) begin
          if (ball_x + VEL_X >= VGA_W - BALL_R) begin
            ball_x <= VGA_W - BALL_R - 1;
            dir_x  <= 1;
          end 
          else begin
            ball_x <= ball_x + VEL_X;
          end
        end 
        else begin
          if (ball_x < BALL_R + VEL_X) begin
            ball_x <= BALL_R;
            dir_x  <= 0;
          end
          else begin
            ball_x <= ball_x - VEL_X;
          end
        end

        if (!dir_y) begin
          if (ball_y + VEL_Y >= VGA_H - BALL_R) begin
            ball_y <= VGA_H - BALL_R - 1;
            dir_y  <= 1;
          end 
          else begin
            ball_y <= ball_y + VEL_Y;
          end
        end 
        else begin
          if (ball_y < BALL_R + VEL_Y) begin
            ball_y <= BALL_R;
            dir_y  <= 0;
          end 
          else begin
            ball_y <= ball_y - VEL_Y;
          end
        end

        wait_cnt <= 0;
        state    <= ST_WAIT;
      end

      // ---- ST_WAIT: pad out to 1/60 s frame period --------------------
      ST_WAIT: begin
        bram_we <= 0;
        if (wait_cnt == WAIT_N - 1) begin
          state <= ST_WRITE;
        end 
        else begin
          wait_cnt <= wait_cnt + 1;
        end
      end

    endcase
  end
end

endmodule
