#include <stdio.h>
#include "xparameters.h"
#include "xgpio.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "sleep.h"

/* Device IDs */
#define GPIO_LED_DEVICE_ID      XPAR_AXI_GPIO_0_DEVICE_ID
#define GPIO_SW_DEVICE_ID       XPAR_AXI_GPIO_1_DEVICE_ID

/* GIC Device ID */
#define INTC_DEVICE_ID          XPAR_SCUGIC_0_DEVICE_ID

/* Interrupt ID */
#define GPIO_INTERRUPT_ID       XPAR_FABRIC_AXI_GPIO_1_IP2INTC_IRPT_INTR

/* GPIO Channel */
#define LED_CHANNEL             1
#define SW_CHANNEL              1

/* Global Instances */
XGpio Gpio_LED;
XGpio Gpio_SW;
XScuGic Intc;

/* LED Pattern */
volatile u8 LedPattern = 0x01;

/* 0 = Left, 1 = Right */
volatile u8 Direction = 0;

/********************************************************
 * Interrupt Service Routine
 ********************************************************/
void BTN_Intr_Handler(void *CallbackRef)
{
    XGpio *GpioPtr = (XGpio *)CallbackRef;

    /* Disable Interrupt */
    XGpio_InterruptDisable(GpioPtr, 1);

    /* Check Interrupt Status */
    if (XGpio_InterruptGetStatus(GpioPtr) & 1)
    {
        /* Change Direction */
        Direction ^= 1;

        printf("IRQ Triggered! Direction = %s\r\n",
               Direction ? "RIGHT" : "LEFT");
    }

    /* Clear Interrupt */
    XGpio_InterruptClear(GpioPtr, 1);

    /* Re-Enable Interrupt */
    XGpio_InterruptEnable(GpioPtr, 1);
}

/********************************************************
 * Interrupt Initialization
 ********************************************************/
int InterruptSystemSetup(XScuGic *IntcPtr, XGpio *GpioPtr)
{
    int Status;
    XScuGic_Config *Config;

    Config = XScuGic_LookupConfig(INTC_DEVICE_ID);

    if(Config == NULL)
        return XST_FAILURE;

    Status = XScuGic_CfgInitialize(
                IntcPtr,
                Config,
                Config->CpuBaseAddress);

    if(Status != XST_SUCCESS)
        return XST_FAILURE;

    Status = XScuGic_Connect(
                IntcPtr,
                GPIO_INTERRUPT_ID,
                (Xil_ExceptionHandler)BTN_Intr_Handler,
                (void *)GpioPtr);

    if(Status != XST_SUCCESS)
        return XST_FAILURE;

    XScuGic_Enable(
        IntcPtr,
        GPIO_INTERRUPT_ID);

    Xil_ExceptionInit();

    Xil_ExceptionRegisterHandler(
        XIL_EXCEPTION_ID_INT,
        (Xil_ExceptionHandler)XScuGic_InterruptHandler,
        IntcPtr);

    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

/********************************************************
 * Main
 ********************************************************/
int main()
{
    int Status;

    printf("\r\n");
    printf("=================================\r\n");
    printf(" HW2 Interrupt Running Light\r\n");
    printf(" IRQ ID = %d\r\n", GPIO_INTERRUPT_ID);
    printf("=================================\r\n");

    /* LED GPIO Init */
    Status = XGpio_Initialize(
                &Gpio_LED,
                GPIO_LED_DEVICE_ID);

    if(Status != XST_SUCCESS)
    {
        printf("LED GPIO Init Failed\r\n");
        return XST_FAILURE;
    }

    XGpio_SetDataDirection(
        &Gpio_LED,
        LED_CHANNEL,
        0x00);

    XGpio_DiscreteWrite(
        &Gpio_LED,
        LED_CHANNEL,
        LedPattern);

    /* SW GPIO Init */
    Status = XGpio_Initialize(
                &Gpio_SW,
                GPIO_SW_DEVICE_ID);

    if(Status != XST_SUCCESS)
    {
        printf("SW GPIO Init Failed\r\n");
        return XST_FAILURE;
    }

    XGpio_SetDataDirection(
        &Gpio_SW,
        SW_CHANNEL,
        0xFF);

    /* Interrupt Init */
    Status = InterruptSystemSetup(
                &Intc,
                &Gpio_SW);

    if(Status != XST_SUCCESS)
    {
        printf("Interrupt Init Failed\r\n");
        return XST_FAILURE;
    }

    /* Enable GPIO Interrupt */
    XGpio_InterruptEnable(
        &Gpio_SW,
        1);

    XGpio_InterruptGlobalEnable(
        &Gpio_SW);

    printf("Interrupt System Ready\r\n");
    printf("Toggle SW to reverse direction\r\n");

    /****************************************************
     * Running Light Loop
     ****************************************************/
    while(1)
    {
        XGpio_DiscreteWrite(
            &Gpio_LED,
            LED_CHANNEL,
            LedPattern);

        usleep(100000);

        if(Direction == 0)
        {
            /* Left Shift */

            if(LedPattern == 0x80)
                LedPattern = 0x01;
            else
                LedPattern <<= 1;
        }
        else
        {
            /* Right Shift */

            if(LedPattern == 0x01)
                LedPattern = 0x80;
            else
                LedPattern >>= 1;
        }
    }

    return 0;
}
