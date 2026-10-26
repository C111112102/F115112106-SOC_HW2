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

# 題目一 ANS

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

![GIC Register](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/IRQ%20Numbers.png)

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

# 題目二 ANS

## Interrupt Port

![PS-PL Signal Groups](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/PS-PL%20Signal%20Groups.png)

UG585 中找到：

```text
PS-PL Signal Groups
```

其中：

```text
PL interrupts to PS = Interrupt Request FPGA to Processor
```

用途：

```text
將 FPGA 產生的 Interrupt 傳送至 ARM Processor。
```

---

## PL Interrupt Signals

![IRQ ID Port](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/PL%20Interrupt%20Signals.png)

UG585 定義：

```text
IRQ_F2P[0] → SPI Number 61
IRQ_F2P[1] → SPI Number 62
IRQ_F2P[2] → SPI Number 63
IRQ_F2P[3] → SPI Number 64
...
```

## IRQ Port Mapping

![IRQ ID Port](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/IRQ%20ID%20Port.png)

UG585 中可看到：

```text

PL - PS Signal Name     Interrupt Name     IRQ ID

    IRQF2P[2:0]             PL[2:0]         63:61
    IRQF2P[7:4]             PL[7:4]         68:64
    IRQF2P[15:8]            PL[15:8]        91:84
```

因此：

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
↓
IRQ61
```
---

# Hardware Design

## Vivado Block Design

![Block](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/Block.png)

本實驗架構：

```text
    SW                 LED
     ↓                  ↓
 AXI_GPIO_1         AXI_GPIO_0
     ↓
ip2intc_irpt
     ↓
 IRQ_F2P[0]
     ↓
    PS
```

---

# Software Design

## 初始化 GIC

程式：

```c
Config = XScuGic_LookupConfig(INTC_DEVICE_ID);

XScuGic_CfgInitialize(
    IntcPtr,
    Config,
    Config->CpuBaseAddress);
```

來源：

```text
xscugic.h
xscugic.c
```

![XScuGic_CfgInitialize](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/XScuGic_CfgInitialize.png)

用途：

```text
取得 GIC 設定資訊
↓
初始化 Distributor
↓
初始化 CPU Interface
↓
建立 GIC Instance
↓
準備接收 Interrupt
```

根據 Xilinx Driver 原始碼：

```c
DistributorInit(InstancePtr, Cpu_Id);
CPUInitialize(InstancePtr);
```

其中：

```text
Distributor = 負責接收與分配 Interrupt

CPU Interface = 負責將 Interrupt 傳送至 CPU
```

因此 `XScuGic_CfgInitialize()` 的作用不只是建立物件，而是完成 GIC 的初始化工作，使 Processing System 能夠接收來自 Programmable Logic 的 Interrupt。

---

## 建立 IRQ 與 ISR 的對應

程式：

```c
XScuGic_Connect(
    IntcPtr,
    GPIO_INTERRUPT_ID,
    (Xil_ExceptionHandler)BTN_Intr_Handler,
    (void *)GpioPtr);
```

來源：

```text
xscugic.c
```
![XScuGic_Connect](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/XScuGic_Connect.png)

核心程式：

```c
InstancePtr->Config->HandlerTable[Int_Id].Handler = Handler;
```

用途：

```text
IRQ61
↓
HandlerTable[61]
↓
BTN_Intr_Handler()
```

建立 Interrupt ID 與 ISR (Interrupt Service Routine) 的對應關係。

當 IRQ61 發生時，GIC 會根據 HandlerTable 找到對應的 ISR 並執行。

---

## 啟用 Interrupt

程式：

```c
XScuGic_Enable(
    IntcPtr,
    GPIO_INTERRUPT_ID
);
```


來源：

```text
xscugic.c
```

![XScuGic_Enable](https://github.com/C111112102/F115112106-SOC_HW2/blob/main/Image/XScuGic_Enable.png)

用途：

```text
設定 GIC Enable Register
↓
啟用 IRQ61
```

啟用後，IRQ61 才能被 GIC 接收與處理。

---

##啟用 GPIO Interrupt

程式：

```c
XGpio_InterruptEnable(
    &Gpio_SW,
    1);
```

```c
XGpio_InterruptGlobalEnable(
    &Gpio_SW);
```

來源：

```text
xgpio.h
xgpio_intr.c
```

用途：

```text
允許 AXI_GPIO_1 產生 Interrupt
```

當 Switch 狀態改變時，即可送出中斷訊號。

---

# Interrupt ID

程式定義：

```c
#define GPIO_INTERRUPT_ID \ XPAR_FABRIC_AXI_GPIO_1_IP2INTC_IRPT_INTR
```

展開後：

```c
#define XPAR_FABRIC_AXI_GPIO_1_IP2INTC_IRPT_INTR 61U
```

來源：

```text
xparameters.h
```

其中：

```text
GPIO_INTERRUPT_ID
↓
61U
↓
IRQ61
↓
IRQ_F2P[0]
```

根據 Zynq-7000 TRM (UG585) IRQ Mapping：

```text
IRQ_F2P[0]
↓
IRQ61
```

因此 GPIO_INTERRUPT_ID 最終對應 IRQ61，也就是 FPGA 傳送至 Processing System 的第一個 PL Interrupt。

---

# Hardware Interrupt Path

根據 Vivado Block Design 及 Verilog：

```verilog
.ip2intc_irpt(axi_gpio_1_ip2intc_irpt)
```

```verilog
.IRQ_F2P(axi_gpio_1_ip2intc_irpt)
```

可追蹤出完整硬體路徑：

```text
SW
↓
AXI_GPIO_1
↓
ip2intc_irpt
↓
IRQ_F2P[0]
↓
IRQ61
```

因此 IRQ61 的實際來源為：

```text
SW
↓
AXI_GPIO_1
↓
ip2intc_irpt
```

而非 Processing System 內部產生。

---

# ISR 設計

Interrupt Service Routine：

```c
void BTN_Intr_Handler(void *CallbackRef)
```

* GIC 接收到 IRQ61 時：

```text
IRQ61
↓
HandlerTable[61]
↓
BTN_Intr_Handler()
```

ISR 主要功能：

```c
Direction ^= 1;
```

利用 XOR 運算切換方向旗標：

```text
0 → 1
1 → 0
```

對應方向：

```text
0 = LEFT
1 = RIGHT
```

因此可以改變 LED 跑馬燈方向：

```text
LEFT
↓
RIGHT

RIGHT
↓
LEFT
```

此外，ISR 內部還會：

```c
XGpio_InterruptDisable(...)
```

暫時關閉中斷。

接著：

```c
XGpio_InterruptClear(...)
```

清除中斷狀態。

最後：

```c
XGpio_InterruptEnable(...)
```

重新開啟中斷。

避免相同中斷被重複觸發。

---

# Interrupt Flow

完整中斷流程如下：

```text
SW
↓
AXI_GPIO_1
↓
ip2intc_irpt
↓
IRQ_F2P[0]
↓
IRQ61
↓
GIC Distributor
↓
GIC CPU Interface
↓
HandlerTable[61]
↓
BTN_Intr_Handler()
↓
Direction ^= 1
↓
LED Running Light Reverse Direction
```

---

# 實驗結果
正常狀態：

```text
LED0
↓
LED1
↓
LED2
↓
...
↓
LED7
```

LED 由左向右移動。

---

當 SW 狀態改變時：

```text
SW
↓
IRQ61
↓
BTN_Intr_Handler()
↓
Direction ^= 1
```

跑馬燈方向反轉：

```text
LED7
↓
LED6
↓
LED5
↓
...
↓
LED0
```

LED 由右向左移動。

---

# 結論

透過閱讀：

```text
UG585
Vivado Block Design
Verilog Source Code
xparameters.h
xscugic.c
```

了解：

- PS (Processing System)
- PL (Programmable Logic)
- IRQ_F2P Interface
- IRQ Mapping
- Generic Interrupt Controller (GIC)
- Interrupt Handler Table

並成功將硬體與軟體中斷流程串接：

```text
SW
↓
AXI_GPIO_1
↓
ip2intc_irpt
↓
IRQ_F2P[0]
↓
IRQ61
↓
GIC
↓
BTN_Intr_Handler()
↓
Direction ^= 1
↓
LED Running Light Reverse Direction
```

成功驗證 Zynq-7020 的 PL → PS Interrupt 機制，以及 GIC 的中斷控制流程。

# 實驗結果影片

[Practical Video](https://github.com/user-attachments/assets/52ea990e-056d-4868-b196-c5ad826df4b3)
