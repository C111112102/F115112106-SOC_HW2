# F115112106-SOC_HW2

HW2 - Zynq7020 Interrupt Control
作業題目
1. 找出 Zynq-7020 相關文件
User Guide
Programming Guide
BSP
2. 找出 UG 中與 Interrupt 相關的 Port
3. 完成 Interrupt 實驗
LED 跑馬燈
SW 觸發 Interrupt
ISR 改變跑馬燈方向
題目一
User Guide
本作業主要參考：

UG585
Zynq-7000 Technical Reference Manual
內容包含：

PS (Processing System)
PL (Programmable Logic)
GIC (Generic Interrupt Controller)
IRQ Mapping
IRQ_F2P
BSP
Vitis 自動產生 BSP Driver：

#include "xgpio.h"
#include "xscugic.h"
#include "xil_exception.h"
提供：

XGpio
XScuGic
等中斷相關函式。

題目二
Interrupt Port
UG585 中找到：

IRQ_F2P[15:0]
代表：

Interrupt Request
FPGA → Processor
用途：

PL(FPGA)
↓
PS(ARM)
傳送 Interrupt。

IRQ Mapping
UG585 中：

IRQ_F2P[0] → SPI 61
IRQ_F2P[1] → SPI 62
IRQ_F2P[2] → SPI 63
...
本實驗使用：

IRQ_F2P[0]
因此對應：

IRQ61
Hardward Design
Vivado Block Design：

SW
↓
AXI_GPIO_1
↓
ip2intc_irpt
↓
IRQ_F2P[0]
↓
PS

LED
↑
AXI_GPIO_0
因此：

AXI_GPIO_1
↓
IRQ_F2P[0]
↓
IRQ61
Software Design
xparameters.h
Vivado Export Hardware 後產生：

#define XPAR_FABRIC_AXI_GPIO_1_IP2INTC_IRPT_INTR 61U
代表：

AXI_GPIO_1 對應 IRQ61
GIC 初始化
XScuGic_CfgInitialize(...)
功能：

初始化 Generic Interrupt Controller (GIC)
GIC 負責管理所有中斷來源。

建立 IRQ 與 ISR 對應
XScuGic_Connect(
    IntcPtr,
    GPIO_INTERRUPT_ID,
    BTN_Intr_Handler,
    ...
);
實際展開後：

XScuGic_Connect(
    IntcPtr,
    61,
    BTN_Intr_Handler,
    ...
);
建立：

IRQ61
↓
BTN_Intr_Handler()
的對應關係。

啟用 Interrupt
XScuGic_Enable(
    IntcPtr,
    GPIO_INTERRUPT_ID
);
啟用：

IRQ61
啟用 GPIO Interrupt
XGpio_InterruptEnable(
    &Gpio_SW,
    1
);

XGpio_InterruptGlobalEnable(
    &Gpio_SW
);
允許：

AXI_GPIO_1
送出中斷訊號。

ISR 設計
中斷服務函式：

void BTN_Intr_Handler(void *CallbackRef)
主要*能：

Direction ^= 1;
切*跑馬燈方向。

LEFT
*
RIGHT

RIGHT
↓
LEFT
IterruptFlow
SW
↓
AXI_GPIO_1
*
ip2intc_irpt
↓
IRQ_F2P*0]
↓
IRQ61
↓
GIC
↓
*TN_Intr_Handler()
↓
Direction ^= 1*↓
LED 跑馬燈反向
#*實驗結果

正常情況：

LED0
↓*LED1
↓
LED2
↓
...
↓
LED*
SW 觸發中斷後：

LED7
↓
LED6
↓
LED5
*
...
↓
LED0
跑馬燈方向*功反轉。

結論
本*驗成功驗證：

PL(FPGA)
↓*IRQ_F2P[0]
↓
IRQ61
↓
*IC
↓
ISR
↓
LED Control*```

完成 Zynq-7020 中斷機*與 PL → PS Interrupt 的應用。
