`timescale 1 ns / 1 ps

module myip_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4,

    // AXI clock frequency
    parameter integer C_S_AXI_CLK_FREQ_HZ = 100000000,

    // LED movement frequency
    parameter integer LED_STEP_HZ = 10
)
(
    output wire [7:0] leds_8bits,
    input  wire [7:0] sws_8bits,
    output wire       irq_out,

    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,

    input wire  [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input wire  [2:0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output wire S_AXI_AWREADY,

    input wire  [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input wire  [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output wire S_AXI_WREADY,

    output wire [1:0] S_AXI_BRESP,
    output wire       S_AXI_BVALID,
    input wire        S_AXI_BREADY,

    input wire  [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input wire  [2:0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output wire S_AXI_ARREADY,

    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire       S_AXI_RVALID,
    input wire        S_AXI_RREADY
);

// ============================================================
// Register map
//
// 0x00 slv_reg0 : LED running-light data (PL -> PS, read-only)
// 0x04 slv_reg1 : Switch status (PL -> PS, read-only)
// 0x08 slv_reg2 : Interrupt clear command (PS -> PL)
// 0x0C slv_reg3 : Interrupt status (PL -> PS, read-only)
//
// sws_8bits[7] = 0 : Forward direction
// sws_8bits[7] = 1 : Reverse direction
// ============================================================

reg [31:0] slv_reg0;
reg [31:0] slv_reg1;
reg [31:0] slv_reg2;
reg [31:0] slv_reg3;

assign leds_8bits = slv_reg0[7:0];
assign irq_out    = slv_reg3[0];

// ============================================================
// LED timer
// Default: 100 MHz clock, one movement every 0.5 second
// ============================================================

localparam integer LED_DIV_COUNT =
    C_S_AXI_CLK_FREQ_HZ / LED_STEP_HZ;

reg [31:0] led_div_count;

wire led_tick = (led_div_count == LED_DIV_COUNT - 1);

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
        led_div_count <= 32'd0;
    else if (led_tick)
        led_div_count <= 32'd0;
    else
        led_div_count <= led_div_count + 1'b1;
end

// ============================================================
// Switch synchronizer
// ============================================================

reg [7:0] sws_meta;
reg [7:0] sws_sync;
reg       sws7_d1;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        sws_meta <= 8'b0;
        sws_sync <= 8'b0;
        sws7_d1  <= 1'b0;
    end
    else begin
        sws_meta <= sws_8bits;
        sws_sync <= sws_meta;
        sws7_d1  <= sws_sync[7];
    end
end

// ============================================================
// slv_reg1: synchronized switch status
// ============================================================

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
        slv_reg1 <= 32'b0;
    else
        slv_reg1 <= {24'b0, sws_sync};
end

// ============================================================
// Automatic LED running light
// Reset release starts at LED0.
// ============================================================

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        slv_reg0 <= 32'h0000_0001;
    end
    else if (led_tick) begin
        if (sws_sync[7] == 1'b0) begin
            // Forward: LED0 -> LED1 -> ... -> LED7 -> LED0
            slv_reg0[7:0] <= {
                slv_reg0[6:0],
                slv_reg0[7]
            };
        end
        else begin
            // Reverse: LED7 -> LED6 -> ... -> LED0 -> LED7
            slv_reg0[7:0] <= {
                slv_reg0[0],
                slv_reg0[7:1]
            };
        end

        slv_reg0[31:8] <= 24'b0;
    end
end

// ============================================================
// AXI4-Lite write channel
// AW and W channels are accepted independently.
// ============================================================

reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
reg [C_S_AXI_DATA_WIDTH-1:0] axi_wdata;
reg [(C_S_AXI_DATA_WIDTH/8)-1:0] axi_wstrb;

reg aw_pending;
reg w_pending;

reg [1:0] axi_bresp;
reg       axi_bvalid;

assign S_AXI_AWREADY = !aw_pending && !axi_bvalid;
assign S_AXI_WREADY  = !w_pending  && !axi_bvalid;

assign S_AXI_BRESP  = axi_bresp;
assign S_AXI_BVALID = axi_bvalid;

wire aw_handshake = S_AXI_AWVALID && S_AXI_AWREADY;
wire w_handshake  = S_AXI_WVALID  && S_AXI_WREADY;

wire write_fire =
    !axi_bvalid &&
    (aw_pending || aw_handshake) &&
    (w_pending  || w_handshake);

wire [C_S_AXI_ADDR_WIDTH-1:0] write_addr =
    aw_pending ? axi_awaddr : S_AXI_AWADDR;

wire [C_S_AXI_DATA_WIDTH-1:0] write_data =
    w_pending ? axi_wdata : S_AXI_WDATA;

wire [(C_S_AXI_DATA_WIDTH/8)-1:0] write_strb =
    w_pending ? axi_wstrb : S_AXI_WSTRB;

wire write_slv_reg2 =
    write_fire && (write_addr[3:2] == 2'b10);

wire clear_irq_command =
    write_slv_reg2 && write_data[0] && write_strb[0];

// Capture write address
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        aw_pending <= 1'b0;
    end
    else begin
        if (write_fire)
            aw_pending <= 1'b0;
        else if (aw_handshake) begin
            axi_awaddr <= S_AXI_AWADDR;
            aw_pending <= 1'b1;
        end
    end
end

// Capture write data
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_wdata  <= {C_S_AXI_DATA_WIDTH{1'b0}};
        axi_wstrb  <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
        w_pending  <= 1'b0;
    end
    else begin
        if (write_fire)
            w_pending <= 1'b0;
        else if (w_handshake) begin
            axi_wdata <= S_AXI_WDATA;
            axi_wstrb <= S_AXI_WSTRB;
            w_pending <= 1'b1;
        end
    end
end

// ============================================================
// slv_reg2: PS interrupt-clear command register
// ============================================================

integer byte_index;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        slv_reg2 <= 32'b0;
    end
    else if (write_slv_reg2) begin
        for (byte_index = 0;
             byte_index < (C_S_AXI_DATA_WIDTH/8);
             byte_index = byte_index + 1) begin

            if (write_strb[byte_index]) begin
                slv_reg2[(byte_index*8) +: 8]
                    <= write_data[(byte_index*8) +: 8];
            end
        end
    end
end

// AXI write response
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_bvalid <= 1'b0;
        axi_bresp  <= 2'b00;
    end
    else begin
        if (write_fire) begin
            axi_bvalid <= 1'b1;
            axi_bresp  <= 2'b00;
        end
        else if (axi_bvalid && S_AXI_BREADY) begin
            axi_bvalid <= 1'b0;
        end
    end
end

// ============================================================
// Interrupt logic
// Any edge on sws_8bits[7] triggers interrupt.
// IRQ remains asserted until PS writes 1 to address 0x08.
// ============================================================

reg irq_reg;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        irq_reg <= 1'b0;
        slv_reg3 <= 32'b0;
    end
    else begin
        if (sws_sync[7] != sws7_d1) begin
            irq_reg  <= 1'b1;
            slv_reg3 <= 32'h0000_0001;
        end
        else if (clear_irq_command) begin
            irq_reg  <= 1'b0;
            slv_reg3 <= 32'h0000_0000;
        end
        else begin
            slv_reg3 <= {31'b0, irq_reg};
        end
    end
end

// ============================================================
// AXI4-Lite read channel
// ============================================================

reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
reg [1:0] axi_rresp;
reg       axi_rvalid;

assign S_AXI_ARREADY = !axi_rvalid;

assign S_AXI_RDATA  = axi_rdata;
assign S_AXI_RRESP  = axi_rresp;
assign S_AXI_RVALID = axi_rvalid;

wire read_handshake = S_AXI_ARVALID && S_AXI_ARREADY;

reg [C_S_AXI_DATA_WIDTH-1:0] read_data_mux;

always @(*) begin
    case (S_AXI_ARADDR[3:2])
        2'b00: read_data_mux = slv_reg0;
        2'b01: read_data_mux = slv_reg1;
        2'b10: read_data_mux = slv_reg2;
        2'b11: read_data_mux = slv_reg3;
        default: read_data_mux = 32'b0;
    endcase
end

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_rdata  <= {C_S_AXI_DATA_WIDTH{1'b0}};
        axi_rresp  <= 2'b00;
        axi_rvalid <= 1'b0;
    end
    else begin
        if (read_handshake) begin
            axi_rdata  <= read_data_mux;
            axi_rresp  <= 2'b00;
            axi_rvalid <= 1'b1;
        end
        else if (axi_rvalid && S_AXI_RREADY) begin
            axi_rvalid <= 1'b0;
        end
    end
end

endmodule
