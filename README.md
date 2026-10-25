# HW2 - Zynq7020 Interrupt Control

## 作業題目

### 題目一

找出：

- User Guide
- Programming Guide
- BSP

並了解 Zynq-7020 Interrupt 架構。

### 題目二

找出 UG 中與 Interrupt 相關的 Port。

### 題目三

完成：

- LED 跑馬燈
- SW 觸發 Interrupt
- ISR 改變跑馬燈方向

---

# 題目一回答

## User Guide

本實驗主要參考：

**UG585 - Zynq-7000 Technical Reference Manual**

從文件中查詢下列重要架構：

- PS (Processing System)
- PL (Programmable Logic)
- GIC (Generic Interrupt Controller)
- IRQ Mapping
- IRQ_F2P Interface

---

## PS (Processing System)

PS 為 Zynq-7020 內建 ARM 系統。

本實驗實際使用：

- ARM Cortex-A9
- GIC
- UART Console

程式對應：

```c
XScuGic Intc;
