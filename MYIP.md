# HW2.1 - Zynq7020 Interrupt Control

## 作業題目

延續HW2第三題，將內建GPIO改成自訂IP，並由硬體部分控制，軟體部分僅提供中斷訊號。自訂 AXI IP 跑馬燈與中斷控制設計

# 題目三(自訂IP) ANS
# Hardware Design

## Vivado Block Design

![Block](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/Block_MYIP.png)

## 1. 系統整體架構 (System Architecture Overview)

移除 Xilinx 官方的 AXI GPIO IP (`axi_gpio_0` 與 `axi_gpio_1`)，改採以 Verilog 完全自訂之 `myip_v1_0` Custom IP，並與 Zynq-7020 PS (Processing System) 進行 AXI4-Lite 匯流排連接與硬體中斷對接。

```text
【Zynq-7020 PS 端 (ARM CPU)】
       │
       ├── AXI4-Lite 匯流排 ───> 【myip_0 (Custom IP - PL 端)】
       │                            ├── 時脈分頻器 (slow_clk) ──> 跑馬燈正反向控制邏輯
       │                            ├── slv_reg0 (0x00) ───────> (保留供 CPU 控制)
       │                            ├── leds_8bits[7:0] ───────> [XDC] ──> 實體 8 顆 LED
       │                            ├── sws_8bits[7:0]  ───────> [XDC] ──> 實體 按鈕/開關
       │                            │     └── sws_8bits[7] ────> 跑馬燈方向控制 (0:正向, 1:反向)
       │                            └── slv_reg2 (0x08) ───────> 中斷手動清除邏輯
       └── IRQ_F2P[0:0] <────────── irq_out (硬體中斷訊號線)
```
## 2. 硬體架構與 RTL 設計 (Hardware RTL Design)
本 IP 採用 雙層階層化設計 (Hierarchical Design)：

頂層模組 (myip_v1_0.v)：作為 IP 的外包裝門面，負責宣告與外部開關、LED 及 PS 端 IRQ 腳位的連線，並將 AXI 匯流排訊號直接透傳給底層。

內層邏輯模組 (myip_v1_0_S00_AXI.v)：包含 AXI4-Lite 暫存器讀寫對映、跑馬燈計數器與中斷手動觸發/清除邏輯。

### RTL 暫存器與 I/O 位址規劃 (Register Map)

|    暫存器 / 腳位   | 位址偏移量 (Offset) |       讀/寫權限      |                       功能與邏輯說明                       |
| ----------------- | ------------------ | -------------------- | -------------------------------------------------------- |
|  leds_8bits[7:0]  |          -         |        輸出 (O)      |        連接實體 LED，由內部跑馬燈邏輯與分頻時脈驅動。        |
|  sws_8bits[7:0]   |   0x04 (slv_reg1)  |        讀取 (R)      | 讀取 8 位元指撥開關/按鈕狀態。sws_8bits[7] 控制跑馬燈方向。  |
|      slv_reg2     |         0x08       |        寫入 (W)      |   中斷清除暫存器：CPU 寫入 0x01 時，將 irq_out 強制降回 0。  |

### 頂層模組程式碼 (myip_v1_0.v)
```v
`timescale 1 ns / 1 ps

module myip_v1_0 #
(
    // Parameters of Axi Slave Bus Interface S00_AXI
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 4
)
(
    // Users to add ports here
    output wire [7:0] leds_8bits,  // 控制 8 顆 LED
    input  wire [7:0] sws_8bits,   // 讀取 8 位元指撥開關/按鈕
    output wire       irq_out,     // 送給 Zynq PS 的中斷訊號線
    // User ports ends

    // Ports of Axi Slave Bus Interface S00_AXI
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire s00_axi_rvalid,
    input wire  s00_axi_rready
);

// Instantiation of Axi Bus Interface S00_AXI
    myip_v1_0_S00_AXI # ( 
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) myip_v1_0_S00_AXI_inst (
        .sws_8bits(sws_8bits),
        .leds_8bits(leds_8bits),
        .irq_out(irq_out),
        .S_AXI_ACLK(s00_axi_aclk),
        .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR(s00_axi_awaddr),
        .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID(s00_axi_awvalid),
        .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA(s00_axi_wdata),
        .S_AXI_WSTRB(s00_axi_wstrb),
        .S_AXI_WVALID(s00_axi_wvalid),
        .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP(s00_axi_bresp),
        .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY(s00_axi_bready),
        .S_AXI_ARADDR(s00_axi_araddr),
        .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID(s00_axi_arvalid),
        .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA(s00_axi_rdata),
        .S_AXI_RRESP(s00_axi_rresp),
        .S_AXI_RVALID(s00_axi_rvalid),
        .S_AXI_RREADY(s00_axi_rready)
    );

endmodule
```
### 內層邏輯模組程式碼 (myip_v1_0_S00_AXI.v)
```v
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

assign slow_clk = clk_div[23]; // 控制跑馬燈流動速度

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

assign leds_8bits = led_reg;

// 3. 中斷觸發與清除邏輯
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
```
## 3. 實體腳位約束 (Pin Constraints - XDC)
```v
# =====================================================================
# 1. 8-bits LED 輸出腳位設定 (LVCMOS33 3.3V 電壓標準)
# =====================================================================
set_property IOSTANDARD LVCMOS33 [get_ports {leds_8bits[*]}]

set_property PACKAGE_PIN T22 [get_ports {leds_8bits[0]}]
set_property PACKAGE_PIN T21 [get_ports {leds_8bits[1]}]
set_property PACKAGE_PIN U22 [get_ports {leds_8bits[2]}]
set_property PACKAGE_PIN U21 [get_ports {leds_8bits[3]}]
set_property PACKAGE_PIN V22 [get_ports {leds_8bits[4]}]
set_property PACKAGE_PIN W22 [get_ports {leds_8bits[5]}]
set_property PACKAGE_PIN U19 [get_ports {leds_8bits[6]}]
set_property PACKAGE_PIN U14 [get_ports {leds_8bits[7]}]

# =====================================================================
# 2. 8-bits 按鈕/開關 輸入腳位設定 (LVCMOS33 3.3V 電壓標準)
# =====================================================================
set_property IOSTANDARD LVCMOS33 [get_ports {sws_8bits[*]}]

set_property PACKAGE_PIN F22 [get_ports {sws_8bits[0]}]
set_property PACKAGE_PIN G22 [get_ports {sws_8bits[1]}]
set_property PACKAGE_PIN H22 [get_ports {sws_8bits[2]}]
set_property PACKAGE_PIN F21 [get_ports {sws_8bits[3]}]
set_property PACKAGE_PIN H19 [get_ports {sws_8bits[4]}]
set_property PACKAGE_PIN H18 [get_ports {sws_8bits[5]}]
set_property PACKAGE_PIN H17 [get_ports {sws_8bits[6]}]
set_property PACKAGE_PIN M15 [get_ports {sws_8bits[7]}]
```
## 4. UG585 手冊對照與 GIC 中斷架構
對照 Xilinx UG585 (Zynq-7000 TRM) 手冊內容：
```text
1.PL-to-PS 中斷 Port：IRQ_F2P[0:0]

2.GIC SPI Interrupt ID：SPI ID #61 (對應硬體 IRQ 通道)

3.GIC 控制器 Base Address：
       Distributor Base Address: 0xF8F0_1000
       CPU Interface Base Address: 0xF8F0_0100
```
## 5. 軟體驅動設計 (Vitis / SDK C Driver)
### C 語言端捨棄官方 xgpio.h 庫，改採底層 xil_io.h 進行暫存器存取與手動中斷清除：
```c
#include <stdio.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xscugic.h"
#include "xil_exception.h"

// 1. 定義自訂 IP 暫存器基底位址與中斷 ID (請對照 xparameters.h)
#define MY_IP_BASEADDR          XPAR_MYIP_0_S00_AXI_BASEADDR
#define INTC_DEVICE_ID          XPAR_SCUGIC_SINGLE_DEVICE_ID

// 對應 UG585 手冊第 7-10 頁的 SPI Interrupt ID (PL[0] 對應 ID 61)
#define INTC_CUSTOM_IP_IRPT_ID  61

// 2. 暫存器偏移量 (Register Offsets) 定義
#define REG_LED_OFFSET          0x00  // slv_reg0: 控制 8 顆 LED 亮滅
#define REG_SW_OFFSET           0x04  // slv_reg1: 讀取 8-bit 指撥開關/按鈕狀態
#define REG_CLR_INTR_OFFSET     0x08  // slv_reg2: 中斷清除暫存器 (寫入 1 手動清除)

// 全域變數
XScuGic IntcInstance;
u32 led_data = 0x01;

// =========================================================================
// 核心：自訂的中斷服務常式 (ISR / Interrupt Service Routine)
// 當按鈕/開關觸發 irq_out 拉高時，ARM CPU 會暫停背景程式，自動跳轉執行此函式
// =========================================================================
void Custom_IP_ISR(void *CallbackRef) {
    // 1. 從 slv_reg1 (0x04) 讀取按鈕/開關目前狀態
    u32 sw_status = Xil_In32(MY_IP_BASEADDR + REG_SW_OFFSET);

    // 2. 翻轉 LED 狀態並寫入 slv_reg0 (0x00) 點亮實體 LED
    led_data = ~led_data;
    Xil_Out32(MY_IP_BASEADDR + REG_LED_OFFSET, led_data);

    printf("Custom IP Interrupt Triggered! SW Status: 0x%02X, LED: 0x%02X\r\n",
           (unsigned int)sw_status, (unsigned int)(led_data & 0xFF));

    // 3. 【最關鍵步驟】：寫入 1 到 slv_reg2 (0x08)
    // 告知 Verilog 手動把 irq_out 降回 0 (清除硬體中斷)，否則 CPU 會卡死在中斷迴圈中！
    Xil_Out32(MY_IP_BASEADDR + REG_CLR_INTR_OFFSET, 0x01);
}

// =========================================================================
// GIC (通用中斷控制器) 初始化與 ISR 向量表註冊
// =========================================================================
int IntcInitFunction(u16 DeviceId) {
    XScuGic_Config *IntcConfig;
    int status;

    // 1. 查找 GIC 控制器配置 (Base Address: 0xF8F01000 / 0xF8F00100)
    IntcConfig = XScuGic_LookupConfig(DeviceId);
    if (IntcConfig == NULL) return XST_FAILURE;

    // 2. 初始化 GIC
    status = XScuGic_CfgInitialize(&IntcInstance, IntcConfig, IntcConfig->CpuBaseAddress);
    if (status != XST_SUCCESS) return XST_FAILURE;

    // 3. 建立並啟用 CPU 異常處理架構 (Exception Handling)
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                 &IntcInstance);
    Xil_ExceptionEnable();

    // 4. 將 Custom IP 的中斷 ID (SPI ID #61) 與自訂 ISR 函式進行註冊綁定
    status = XScuGic_Connect(&IntcInstance, INTC_CUSTOM_IP_IRPT_ID,
                             (Xil_ExceptionHandler)Custom_IP_ISR,
                             NULL);
    if (status != XST_SUCCESS) return XST_FAILURE;

    // 5. 在 GIC 控制器中致能該筆中斷 ID
    XScuGic_Enable(&IntcInstance, INTC_CUSTOM_IP_IRPT_ID);

    return XST_SUCCESS;
}

// =========================================================================
// 主程式 (Main Routine)
// =========================================================================
int main() {
    int status;

    printf("=== Zynq 7020 Custom IP Interrupt Test Start ===\r\n");

    // 1. 寫入 slv_reg0 初始化 LED 狀態
    Xil_Out32(MY_IP_BASEADDR + REG_LED_OFFSET, led_data);

    // 2. 初始化 GIC 中斷系統並註冊 ISR
    status = IntcInitFunction(INTC_DEVICE_ID);
    if (status != XST_SUCCESS) {
        printf("GIC & Interrupt Setup Failed!\r\n");
        return XST_FAILURE;
    }

    printf("Interrupt System Initialized Successfully. Waiting for SW trigger...\r\n");

    // 3. 背景無窮迴圈 (CPU 待命，硬體中斷觸發時自動跳轉至 Custom_IP_ISR)
    while (1) {
    }

    return 0;
}
```

## 6. 實驗結果驗證
1. Vivado Block Design 畫面：myip_0 成功取代 GPIO IP，且 irq_out 連接至 Zynq PS 的 IRQ_F2P[0:0]。

2. 跑馬燈功能：
```text
當 SW7 = 0 時，8 顆 LED 呈現正向（向左）迴圈跑馬燈[cite: 2]。

當 SW7 = 1 時，8 顆 LED 即時切換為反向（向右）迴圈跑馬燈[cite: 2]。
```
3. 中斷功能：撥動任一指撥開關或按下按鈕時，Vitis Terminal 正確印出中斷訊息，證明硬體觸發與 slv_reg2 手動中斷清除邏輯運作正常。

# 實驗結果影片

[Practical Video](https://www.youtube.com/watch?v=DFJ1LbRWHDc)
