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
