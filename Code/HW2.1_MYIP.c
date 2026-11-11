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
