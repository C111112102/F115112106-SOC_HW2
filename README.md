# HW2 - Zynq7020 Interrupt Control

## 作業題目

### 題目一

查找：

- User Guide
- Programming Guide
- BSP

並了解 Zynq-7020 Interrupt 架構。

### 題目二

找出 UG 中與 Interrupt 相關的 Port。

### 題目三

實作：

- LED 跑馬燈
- SW 觸發 Interrupt
- ISR 改變跑馬燈方向

---

# 題目一回答

## 參考文件

### UG585

Zynq-7000 Technical Reference Manual

透過 UG585 查詢：

- PS (Processing System)
- PL (Programmable Logic)
- GIC (Generic Interrupt Controller)
- IRQ Mapping
- IRQ_F2P Interface

---

## PS (Processing System)

PS 為 Zynq-7020 內建 ARM 處理器系統。

主要包含：

- ARM Cortex-A9
- Generic Interrupt Controller (GIC)
- UART
- DDR Controller

本實驗中的程式皆執行於 PS。

---

## PL (Programmable Logic)

PL 為 FPGA 可程式化邏輯區。

本實驗中使用：

```text
AXI_GPIO_0
AXI_GPIO_1
```

功能如下：

```text
AXI_GPIO_0
↓
LED

AXI_GPIO_1
↓
SW
```

---

## Generic Interrupt Controller (GIC)

GIC 為 Generic Interrupt Controller。

功能：

```text
管理所有 Interrupt
```

當中斷進入 PS 後：

```text
IRQ61
↓
GIC
↓
BTN_Intr_Handler()
```

GIC 負責將 Interrupt 對應至正確 ISR。

程式中使用：

```c
XScuGic_CfgInitialize(...)
```

```c
XScuGic_Connect(...)
```

```c
XScuGic_Enable(...)
```

---

## GIC Registers

![GIC Register](image/Pending_Register.png)

由 UG585 查詢到重要 Register：

### ICCIAR

Interrupt Acknowledge Register

用途：

```text
取得目前發生的 Interrupt ID
```

例如：

```text
IRQ61
```

---

### ICCHPIR

Highest Pending Interrupt Register

用途：

```text
查看目前等待服務的 Interrupt
```

本實驗中主要等待服務的中斷為：

```text
IRQ61
```

---

### ICCEOIR

End Of Interrupt Register

用途：

```text
通知 GIC Interrupt 已完成處理
```

---

# 題目二回答

## Interrupt Port

UG585 中找到：

```text
IRQ_F2P[15:0]
```

其中：

```text
IRQ_F2P
=
Interrupt Request FPGA to Processor
```

用途：

```text
PL
↓
PS
```

將 FPGA 產生的 Interrupt 傳送至 ARM Processor。

---

## IRQ Port Mapping

![IRQ Port](image/IRQ_ID_Port.png)

UG585 中可看到：

```text
PL[2:0]
↓
IRQF2P[2:0]
↓
IRQ63~61
```

因此：

```text
IRQ_F2P[0]
↓
IRQ61
```

---

## IRQ Mapping

![IRQ Mapping](image/IRQ_numbers.jpg)

UG585 定義：

```text
IRQ_F2P[0] → IRQ61
IRQ_F2P[1] → IRQ62
IRQ_F2P[2] → IRQ63
IRQ_F2P[3] → IRQ64
...
```

本實驗中使用：

```text
IRQ_F2P[0]
```

因此：

```text
IRQ_F2P[0]
↓
IRQ61
```

---

# Hardware Design

## Vivado Block Design

本實驗架構：

```text
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
```

因此形成：

```text
AXI_GPIO_1
↓
IRQ_F2P[0]
↓
IRQ61
```

這與 UG585 的定義完全一致。

---

# Software Design

## xparameters.h

Vivado Export Hardware 後，

Vitis 自動產生：

```c
#define XPAR_FABRIC_AXI_GPIO_1_IP2INTC_IRPT_INTR 61U
```

代表：

```text
AXI_GPIO_1 Interrupt
↓
IRQ61
```

其中：

```text
61U
=
Unsigned Integer 61
```

此數值是由 Vivado 根據硬體連線自動產生。

---

## 初始化 GIC

程式：

```c
XScuGic_CfgInitialize(...)
```

用途：

```text
初始化 Generic Interrupt Controller
```

---

## 建立 IRQ 與 ISR 的對應

程式：

```c
XScuGic_Connect(
    IntcPtr,
    GPIO_INTERRUPT_ID,
    BTN_Intr_Handler,
    ...
);
```

實際效果：

```text
IRQ61
↓
BTN_Intr_Handler()
```

建立 IRQ 與 ISR 對應關係。

---

## 啟用 Interrupt

程式：

```c
XScuGic_Enable(
    IntcPtr,
    GPIO_INTERRUPT_ID
);
```

用途：

```text
允許 IRQ61 進入 GIC
```

---

## 啟用 GPIO Interrupt

程式：

```c
XGpio_InterruptEnable(...)
```

```c
XGpio_InterruptGlobalEnable(...)
```

用途：

```text
允許 AXI_GPIO_1 產生 Interrupt
```

---

# ISR 設計

Interrupt Service Routine：

```c
void BTN_Intr_Handler(void *CallbackRef)
```

當 IRQ61 發生時執行。

*要功能：

```c
Direction ^= 1;
```

切換*馬燈方向。

```text
LEFT
↓
RIGHT

RIGHT*↓
*EFT
```

---

# Interrupt Flow

``*text
SW
↓
AXI_GPIO_1
↓
ip2intc_irp**↓
IRQ_F2P[0]
↓
IRQ61
*
GIC
↓
BTN_Intr_Handler()
↓
Direct*on*^= 1
↓
LED 跑馬燈反向
*``

---

# 實驗結果

正常狀態：

```*ext
LED0
↓
LED1
↓
LED2
*
...
↓
LED7
```

向左移動。

*--

SW 觸發 Interrupt：

```text
IRQ6*
↓*BTN_Intr_Handler()
↓
Direction ^= *
```

變成：

```text
LED7
↓
LED6
↓*LED5
↓
...
↓
LED0
```

向*g System)
- PL (Programmable Logic)
- IRQ_F2P
- IRQ Mapping
- GIC Registers

並成功將：

```text
SW
↓
AXI_GPIO_1
↓
IRQ_F2P[0]
↓
IRQ61
↓
GIC
↓
BTN_Intr_Handler()
↓
LED Running Light
```

完整串接。

成功驗證 Zynq-7020 的 PL → PS Interrupt 機制以及 GIC 中斷控制流程。
