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
Distributor
=
負責接收與分配 Interrupt

CPU Interface
=
負責將 Interrupt 傳送至 CPU
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

*``text
xscugic.c
``*

核心程式：

```c
InstancePtr*>Config->HandlerTable[Int_Id].Hand*er
*       = Handler;
```

用途：

```tex**IRQ61
↓
HandlerTable[61*
↓
BTN_Intr_Handler()
```

建立 Inte*rupt ID 與 ISR（Interrupt*Service Routine*的對應關係。

當 IRQ61 發*時，GIC 會*據 HandlerTable 找*對應的 ISR 並*行。

---

## 啟用 Interrupt

*式：

```c
XScuG*c_Enable(
    IntcPtr,
    GPIO*INTERRUPT_ID
);
```

來源：

```text*xscugic.c
```

用途*

```text
設定 GIC Enable Register
*
啟用 IRQ61
```

*用後，IRQ*1 才能被*GIC 接收與處理。

---

##*啟用 GPIO Interrupt

程式：

```*
XGpio_InterruptEnable(
   *&Gpio_SW,
    1);
``*

```c
XGpio_InterruptGlobal*nable(
    &Gpio_SW);
```

*源：

```text
xgpio.h
x*pio_intr.c
```

用途：

```text*允許 AXI_GPIO_1 產* Interrupt
```

當 Switch 狀態*變時，即可送出中斷*號。

---

# Interrupt ID

程式*義：

```c
#define GPIO_INTERRUPT_ID*\
        XPAR_FABRIC_AXI_GPIO_*_IP2INTC_IRPT_INTR
``*

展開後：

```c
#define X*AR_FABRIC_AXI_GPIO_1_IP2*NTC_IRPT_INTR 61U
``*

來源：

```text
xparameters.h
*``

其中：

```text
GPIO_INTERRUPT_ID*↓
61U
↓
IRQ61*↓
IRQ_F2P[0]
```

根據 Zynq-7000*TRM（UG585）IRQ Mapping：

```*ext
IRQ_F2P[0] →*IRQ61
```

因此 GPIO*INTERRUPT_ID 最終對應：

```text
*RQ61
```

也就是 FPGA 傳*至 Processing System 的第一個 PL Interr*pt。

*--

# Hardware Interrupt Path

根據 *ivado*Block Design 及 Verilog：

```*erilog
.ip2intc_irpt(axi_gpio_1_ip*intc_irpt*
```

```verilog
.IRQ_F*P(axi_gpio_1_ip2int*_irpt)
```

可追蹤*完整硬體路徑：

```text*SW
↓
AXI_GPIO*1
↓
ip2intc_ir*t
↓
IRQ_F2P[0]
↓
IRQ61
```

因此 IRQ*1 的實際來源為：

```text
*W
↓
AXI*GPIO_1
↓
ip2intc*irpt
```

而* Processing System 內部*生。

---

# ISR 設計

*nterrupt Service Routine：

```c
vo*d BTN_In*r_Handler(void *CallbackRef)
```

* GIC 接收到 IRQ61 時：

```text*IRQ61
↓
HandlerTable[61]
↓
BTN_Int*_Handler()
```

*SR 主要功能：

```*
Direction ^= 1;
```

利用*XOR 運算切換方向旗標：

*``text
0 → 1
1 →*0
```

對應方向：

```*ext
0 = LEFT
1 = RIGHT
*``

因此可以改變 LED 跑馬*方向：

```text
LEFT
*
RIGHT

RIGHT
↓
LEFT
*``

此外，*SR 內部還會：

```c
*Gpio_InterruptDisable(...)
*``

*時關*中斷，

接*：

```c
XGpio_Interrupt*lear(...)
```

清除中斷*態，

最後：

```c
XG*io_InterruptEnable(...)
```

重新*啟中斷*

避免相*中斷被重複觸*。

---

# Interrupt Flow

完整中*流程如下：

```text
SW
↓*AXI_GPIO_1
↓
ip*intc_irpt
↓
IRQ_F*P[0]
↓
IRQ61
*
GIC Distributor
↓
GIC*CPU Interface
↓
HandlerTable[61]
↓*BTN_Intr_Handler()
↓
Direction ^= *
↓
LED Running Light Reverse Direc*ion
```

---

# 實驗結果*
正常狀態：

```text
LED0
↓
LED1
↓
LED*
↓
...
↓
LED7
```

LED 由左向右移動*

---

當 SW 狀態改變時*

```text
SW
↓
IRQ61*↓
BTN_Intr_Handler()
↓
*irection ^= 1
```

跑馬*方向反轉：

```text
LED7*↓
LED6
↓
LED5
↓
...
↓
LED0
``*

LED 由右向左移動。

*--

# 結論

透過閱讀：

*``text
UG585
*ivado Block Design
Verilog Source *ode
xparameters.h
xscugic.c
```

了*：

- PS（Processing System）
- PL（Pr*grammable Logic）
- IRQ_F2P Interfa*e
- IRQ Mapping
- Generic Interrup* Controller（GIC）
- Interrupt Handl*r Table

並成功將硬體與軟體中斷流程串接：

```text*SW
↓
AXI_GPIO_1
↓
ip2intc*irpt
↓
IRQ_F2P[*]
↓
IRQ61
↓
G*C
↓
BTN_Intr_Handler()
↓*Direction ^= 1
↓
LED Running*Light Reverse Direction
```

成功驗證 **nq-7020 的 PL → PS Interrupt 機制，以及 *IC 的中斷控制流程。

# 實驗結果影片

[Practical Video](https://github.com/user-attachments/assets/52ea990e-056d-4868-b196-c5ad826df4b3)
