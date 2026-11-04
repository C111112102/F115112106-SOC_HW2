`timescale 1 ns / 1 ps

	module myip_v1_0_S00_AXI #
	(
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		parameter integer C_S_AXI_ADDR_WIDTH	= 4
	)
	(
		// Users to add ports here
		output wire [7:0] leds_8bits,  // 控制 8 顆 LED (由跑馬燈或 slv_reg0 驅動)
		input  wire [7:0] sws_8bits,   // 讀取 8 位元按鈕/開關 (sws_8bits[7] 控制方向)
		output wire       irq_out,     // 傳送給 Zynq PS 的中斷訊號線
		// User ports ends
		// Do not modify the ports beyond this line

		input wire  S_AXI_ACLK,
		input wire  S_AXI_ARESETN,
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		input wire [2 : 0] S_AXI_AWPROT,
		input wire  S_AXI_AWVALID,
		output wire  S_AXI_AWREADY,
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		input wire  S_AXI_WVALID,
		output wire  S_AXI_WREADY,
		output wire [1 : 0] S_AXI_BRESP,
		output wire  S_AXI_BVALID,
		input wire  S_AXI_BREADY,
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		input wire [2 : 0] S_AXI_ARPROT,
		input wire  S_AXI_ARVALID,
		output wire  S_AXI_ARREADY,
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		input wire [1 : 0] S_AXI_RRESP,
		input wire  S_AXI_RVALID,
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 1;

	// Slave Registers 
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
	wire	 slv_reg_rden;
	wire	 slv_reg_wren;
	reg [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;
	integer	 byte_index;
	reg	 aw_en;

	// I/O Connections assignments
	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA	= axi_rdata;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;

	// Implement axi_awready generation
	always @( posedge S_AXI_ACLK ) begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	      axi_awready <= 1'b0;
	      aw_en <= 1'b1;
	    end 
	  else begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
	          axi_awready <= 1'b1;
	          aw_en <= 1'b0;
	        end
	        else if (S_AXI_BREADY && axi_bvalid) begin
	              aw_en <= 1'b1;
	              axi_awready <= 1'b0;
	            end
	      else begin
	          axi_awready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_awaddr latching
	always @( posedge S_AXI_ACLK ) begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	      axi_awaddr <= 0;
	    end 
	  else begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
	          axi_awaddr <= S_AXI_AWADDR;
	        end
	    end 
	end       

	// Implement axi_wready generation
	always @( posedge S_AXI_ACLK ) begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	      axi_wready <= 1'b0;
	    end 
	  else begin    
	      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en ) begin
	          axi_wready <= 1'b1;
	        end
	      else begin
	          axi_wready <= 1'b0;
	        end
	    end 
	end       

	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

	// Implement memory mapped register write logic
	always @( posedge S_AXI_ACLK ) begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	      slv_reg0 <= 0;
	      slv_reg1 <= 0;
	      slv_reg2 <= 0;
	      slv_reg3 <= 0;
	    end 
	  else begin
	    if (slv_reg_wren) begin
	        case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          2'h0:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          2'h1:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          2'h2:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          2'h3:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          default : begin
	                      slv_reg0 <= slv_reg0;
	                      slv_reg1 <= slv_reg1;
	                      slv_reg2 <= slv_reg2;
	                      slv_reg3 <= slv_reg3;
	                    end
	        endcase
	      end
	  end
	end    

	// Implement write response logic generation
	always @( posedge S_AXI_ACLK ) begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	      axi_bvalid  <= 0;
	      axi_bresp   <= 2'b0;
	    end 
	  else begin    
	      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
	          axi_bvalid <= 1'b1;
	          axi_bresp  <= 2'b0;
	        end                   
	      else begin
	          if (S_AXI_BREADY && axi_bvalid) begin
	              axi_bvalid <= 1'b0; 
	            end  
	        end
	    end
	end   

	// Implement axi_arready & axi_araddr latching
	always @( posedge S_AXI_ACLK ) begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	      axi_arready <= 1'b0;
	      axi_araddr  <= 32'b0;
	    end 
	  else begin    
	      if (~axi_arready && S_AXI_ARVALID) begin
	          axi_arready <= 1'b1;
	          axi_araddr  <= S_AXI_ARADDR;
	        end
	      else begin
	          axi_arready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_rvalid generation
	always @( posedge S_AXI_ACLK ) begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	      axi_rvalid <= 0;
	      axi_rresp  <= 0;
	    end 
	  else begin    
	      if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
	          axi_rvalid <= 1'b1;
	          axi_rresp  <= 2'b0;
	        end   
	      else if (axi_rvalid && S_AXI_RREADY) begin
	          axi_rvalid <= 1'b0;
	        end                
	    end
	end   

	// Implement memory mapped register read logic (讀取開關狀態)
	assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
	always @(*) begin
	      case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	        2'h0   : reg_data_out <= slv_reg0;
	        2'h1   : reg_data_out <= {24'b0, sws_8bits}; // 讀取實體開關狀態
	        2'h2   : reg_data_out <= slv_reg2;
	        2'h3   : reg_data_out <= slv_reg3;
	        default : reg_data_out <= 0;
	      endcase
	end

	// Output register or memory read data
	always @( posedge S_AXI_ACLK ) begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	      axi_rdata  <= 0;
	    end 
	  else begin    
	      if (slv_reg_rden) begin
	          axi_rdata <= reg_data_out;
	        end   
	    end
	end   

	// =========================================================================
	// Add user logic here (跑馬燈正反向控制 + 中斷機制)
	// =========================================================================

	// 1. 時脈分頻器 (將 50MHz / 100MHz 降速，讓肉眼看得清跑馬燈)
	reg [25:0] clk_div;
	wire slow_clk;

	always @(posedge S_AXI_ACLK) begin
	    if (!S_AXI_ARESETN)
	        clk_div <= 26'd0;
	    else
	        clk_div <= clk_div + 1'b1;
	end

	assign slow_clk = clk_div[22]; // 可調整位元來改變跑馬燈流動速度

	// 2. 跑馬燈正反向邏輯 (以開關 sws_8bits[7] 作為方向控制：0為正向，1為反向)
	reg [7:0] led_reg;

	always @(posedge slow_clk or negedge S_AXI_ARESETN) begin
	    if (!S_AXI_ARESETN) begin
	        led_reg <= 8'b0000_0001;
	    end else begin
	        if (sws_8bits[7] == 1'b0) begin
	            // 【正向跑馬燈】：向左迴圈移動 (Bit 0 -> 1 -> 2 ... -> 7 -> 0)
	            led_reg <= {led_reg[6:0], led_reg[7]};
	        end else begin
	            // 【反向跑馬燈】：向右迴圈移動 (Bit 7 -> 6 -> 5 ... -> 0 -> 7)
	            led_reg <= {led_reg[0], led_reg[7:1]};
	        end
	    end
	end

	// 將跑馬燈結果輸出給實體 LED (若想改由 CPU 透過 slv_reg0 控制，可在此處切換)
	assign leds_8bits = led_reg;

	// 3. 原本的中斷觸發與清除邏輯
	reg irq_reg;
	reg [7:0] sws_d1;

	// 解碼 AXI 寫入位址：判斷 CPU 是否正在寫入 slv_reg2 (位址偏移量 0x08)
	wire slv_reg2_wren = slv_reg_wren && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 2'h2);

	always @(posedge S_AXI_ACLK) begin
	    if (!S_AXI_ARESETN) begin
	        sws_d1  <= 8'b0;
	        irq_reg <= 1'b0;
	    end else begin
	        sws_d1 <= sws_8bits;
	        
	        // 條件 A：當偵測到開關/按鈕狀態發生改變時，拉高中斷訊號
	        if (sws_8bits != sws_d1) begin
	            irq_reg <= 1'b1;
	        end 
	        // 條件 B：當 CPU 寫入 1 到 slv_reg2 (0x08) 時，手動清除中斷旗標
	        else if (slv_reg2_wren && S_AXI_WDATA[0] == 1'b1) begin
	            irq_reg <= 1'b0;
	        end
	    end
	end

	assign irq_out = irq_reg;

	// User logic ends

endmodule
