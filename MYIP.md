# HW2.1 - Zynq7020 Interrupt Control

## 作業題目

延續HW2第三題，將內建GPIO改成自訂IP，並由硬體部分控制，軟體部分僅提供中斷訊號。
自訂 AXI IP 跑馬燈與中斷控制設計。

# 題目三(自訂IP) ANS
# Hardware Design

## Vivado Block Design

![Block](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/Block_MYIP.png)


## 1. 系統整體架構 (System Architecture Overview)

本專案移除 Xilinx 官方的 AXI GPIO IP (`axi_gpio_0` 與 `axi_gpio_1`)，改採以 Verilog 完全自訂之 `myip_v1_0` Custom IP，並與 Zynq-7020 PS (Processing System) 進行 AXI4-Lite 匯流排連接與硬體中斷對接。

在本架構中，跑馬燈的燈號點亮與移位邏輯完全由 **C 語言（ARM CPU）中斷服務常式 (ISR)** 被動驅動與控制；Verilog RTL 負責 AXI 位址解碼、按鈕邊緣狀態偵測及 Handshake 中斷旗標手動清除機制。

```text
【Zynq-7020 PS 端 (ARM CPU)】
       │
       ├── AXI4-Lite 匯流排 ───> 【myip_0 (Custom IP - PL 端)】
       │                            ├── slv_reg0 (0x00) ───────> leds_8bits[7:0] ──> [XDC] ──> 實體 8 顆 LED
       │                            ├── slv_reg1 (0x04) <─────── sws_8bits[7:0]  <── [XDC] ──> 實體 按鈕/開關
       │                            └── slv_reg2 (0x08) ───────> 中斷手動清除邏輯 (Handshake Clear)
       └── IRQ_F2P[0:0] <────────── irq_out (硬體中斷訊號線)
```

## 2. 硬體架構與 RTL 設計 (Hardware RTL Design)
本 IP 採用 雙層階層化設計 (Hierarchical Design)：

頂層模組 (myip_v1_0.v)：作為 IP 的外包裝門面，負責宣告與外部開關、LED 及 PS 端 IRQ 腳位的連線，並將 AXI 匯流排訊號直接透傳給底層。

內層邏輯模組 (myip_v1_0_S00_AXI.v)：包含 AXI4-Lite 暫存器解碼、LED 輸出指派與中斷訊號生成/手動清除邏輯。

### RTL 暫存器與 I/O 位址規劃 (Register Map)

|    暫存器 / 腳位   | 位址偏移量 (Offset) |       讀/寫權限      |                       功能與邏輯說明                       |
| ----------------- | ------------------ | -------------------- | -------------------------------------------------------- |
| slv_reg0[7:0] / leds_8bits[7:0]  |          -         |        輸出 (O)      |        連接實體 LED，由內部跑馬燈邏輯與分頻時脈驅動。        |
|  slv_reg2 (中斷清除) / sws_8bits[7:0]   |   0x04 (slv_reg1)  |        讀取 (R)      | 讀取 8 位元指撥開關/按鈕狀態。sws_8bits[7] 控制跑馬燈方向。  |
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
// Add user logic here

// ------------------------------------------------------------
// 1. 輸出腳位綁定
// ------------------------------------------------------------
assign leds_8bits = slv_reg0[7:0];
assign irq_out    = slv_reg3[0];

// ------------------------------------------------------------
// 2. LED 除頻計時器 (100 MHz -> 10 Hz)
// ------------------------------------------------------------
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

// ------------------------------------------------------------
// 3. 開關非同步訊號兩級同步器與邊緣暫存
// ------------------------------------------------------------
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

// ------------------------------------------------------------
// 4. slv_reg1: 更新同步後的開關狀態供 PS 讀取
// ------------------------------------------------------------
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
        slv_reg1 <= 32'b0;
    else
        slv_reg1 <= {24'b0, sws_sync};
end

// ------------------------------------------------------------
// 5. slv_reg0: 自動正反向跑馬燈邏輯 (Reset 後從 LED0 開始)
// ------------------------------------------------------------
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

// ------------------------------------------------------------
// 6. slv_reg3 & irq_out: 中斷觸發與手動清除邏輯
// ------------------------------------------------------------
reg irq_reg;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        irq_reg  <= 1'b0;
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

// User logic ends
```
## 3. Pin Constraints - XDC
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
#include "xil_types.h"
#include "xstatus.h"

// ============================================================
// 1. 自訂 IP 基底位址與中斷 ID
// ============================================================

#define MY_IP_BASEADDR          XPAR_MYIP_0_S00_AXI_BASEADDR

#define INTC_DEVICE_ID          XPAR_SCUGIC_SINGLE_DEVICE_ID

// 若 PL IRQ 接到 IRQ_F2P[0]，Zynq-7000 通常對應 SPI ID 61
#define INTC_CUSTOM_IP_IRPT_ID  61

// ============================================================
// 2. AXI4-Lite 暫存器位址
// ============================================================

#define REG_LED_OFFSET          0x00
#define REG_SW_OFFSET           0x04
#define REG_CLR_INTR_OFFSET     0x08
#define REG_INTR_STATUS_OFFSET  0x0C

// ============================================================
// 3. 全域變數
// ============================================================

XScuGic IntcInstance;

// ============================================================
// 4. 自訂 IP 中斷服務常式
// ============================================================

void Custom_IP_ISR(void *CallbackRef)
{
    u32 led_status;
    u32 sw_status;
    u32 intr_status;

    // 讀取目前 LED 狀態
    led_status = Xil_In32(
        MY_IP_BASEADDR + REG_LED_OFFSET
    );

    // 讀取目前開關狀態
    sw_status = Xil_In32(
        MY_IP_BASEADDR + REG_SW_OFFSET
    );

    // 讀取中斷狀態
    intr_status = Xil_In32(
        MY_IP_BASEADDR + REG_INTR_STATUS_OFFSET
    );

    xil_printf("\r\n========== Interrupt ==========\r\n");

    xil_printf("Switch Status : 0x%02X\r\n",
               (unsigned int)(sw_status & 0xFF));

    xil_printf("LED Status    : 0x%02X\r\n",
               (unsigned int)(led_status & 0xFF));

    xil_printf("Interrupt     : 0x%08X\r\n",
               (unsigned int)intr_status);

    // 判斷 SW7 狀態
    if (sw_status & 0x80)
    {
        xil_printf("SW7 = HIGH : Reverse Direction\r\n");
    }
    else
    {
        xil_printf("SW7 = LOW  : Forward Direction\r\n");
    }

    // ========================================================
    // 清除 PL 端中斷
    // 寫入 slv_reg2 (0x08) = 1
    // ========================================================

    Xil_Out32(
        MY_IP_BASEADDR + REG_CLR_INTR_OFFSET,
        0x01
    );

    xil_printf("Interrupt Cleared!\r\n");
}

// ============================================================
// 5. GIC 初始化與中斷註冊
// ============================================================

int IntcInitFunction(u16 DeviceId)
{
    XScuGic_Config *IntcConfig;
    int status;

    // 查找 GIC 設定
    IntcConfig = XScuGic_LookupConfig(DeviceId);

    if (IntcConfig == NULL)
    {
        return XST_FAILURE;
    }

    // 初始化 GIC
    status = XScuGic_CfgInitialize(
        &IntcInstance,
        IntcConfig,
        IntcConfig->CpuBaseAddress
    );

    if (status != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    // 初始化 CPU Exception
    Xil_ExceptionInit();

    // 註冊 GIC 中斷處理函式
    Xil_ExceptionRegisterHandler(
        XIL_EXCEPTION_ID_INT,
        (Xil_ExceptionHandler)XScuGic_InterruptHandler,
        &IntcInstance
    );

    // 設定 PL 中斷觸發方式
    XScuGic_SetPriorityTriggerType(
        &IntcInstance,
        INTC_CUSTOM_IP_IRPT_ID,
        0xA0,
        0x01
    );

    // 將自訂 IP 中斷與 ISR 綁定
    status = XScuGic_Connect(
        &IntcInstance,
        INTC_CUSTOM_IP_IRPT_ID,
        (Xil_ExceptionHandler)Custom_IP_ISR,
        NULL
    );

    if (status != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    // 啟用 GIC 中斷
    XScuGic_Enable(
        &IntcInstance,
        INTC_CUSTOM_IP_IRPT_ID
    );

    // 啟用 CPU 中斷
    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

// ============================================================
// 6. Main
// ============================================================

int main(void)
{
    int status;

    xil_printf("\r\n");
    xil_printf("====================================\r\n");
    xil_printf(" Zynq-7020 LED Running Light System\r\n");
    xil_printf("====================================\r\n");

    // 初始化 GIC
    status = IntcInitFunction(INTC_DEVICE_ID);

    if (status != XST_SUCCESS)
    {
        xil_printf("GIC Initialization Failed!\r\n");
        return XST_FAILURE;
    }

    xil_printf("Interrupt System Initialized!\r\n");

    xil_printf("LED Running Light Started!\r\n");

    xil_printf("SW7 LOW  : Forward Direction\r\n");
    xil_printf("SW7 HIGH : Reverse Direction\r\n");

    xil_printf("Waiting for SW7 Interrupt...\r\n");

    // 背景無窮迴圈
    while (1)
    {
        // LED 跑馬燈由 PL 自動控制
        // PS 等待 PL 發出中斷
    }

    return XST_SUCCESS;
}

```

## 6. 實驗結果驗證
1. Vivado Block Design 畫面：myip_0 成功取代 GPIO IP，且 irq_out 連接至 Zynq PS 的 IRQ_F2P[0:0]。

2. 跑馬燈功能：
```text
當 SW7 = 0 時，8 顆 LED 呈現正向（向左）迴圈跑馬燈。

當 SW7 = 1 時，8 顆 LED 即時切換為反向（向右）迴圈跑馬燈。
```
3. 中斷功能：撥動任一指撥開關或按下按鈕時，Vitis Terminal 正確印出中斷訊息，證明硬體觸發與 slv_reg2 手動中斷清除邏輯運作正常。

# 實驗結果影片

[Practical Video](https://www.youtube.com/watch?v=DFJ1LbRWHDc)
