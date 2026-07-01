#include <stdio.h>
#include <stdint.h>

// APB Multiplier registers
#define MULT_BASE       0x00011400
#define MULT_OPERAND_A  (MULT_BASE + 0x00)
#define MULT_OPERAND_B  (MULT_BASE + 0x04)
#define MULT_RESULT_LO  (MULT_BASE + 0x08)
#define MULT_RESULT_HI  (MULT_BASE + 0x0C)
#define MULT_CONTROL    (MULT_BASE + 0x10)
#define MULT_STATUS     (MULT_BASE + 0x14)

// Helper functions for APB access
static inline void apb_write(uint32_t addr, uint32_t data) {
    volatile uint32_t* ptr = (volatile uint32_t*)addr;
    *ptr = data;
}

static inline uint32_t apb_read(uint32_t addr) {
    volatile uint32_t* ptr = (volatile uint32_t*)addr;
    return *ptr;
}

void delay(int cycles) {
    for (volatile int i = 0; i < cycles; i++);
}

int main() {
    printf("\n=================================\n");
    printf("APB Multiplier Peripheral Test\n");
    printf("=================================\n\n");
    
    printf("Multiplier base: 0x%08x\n", MULT_BASE);
    printf("About to access multiplier...\n");
    
    // Test 1: Try to write
    printf("Writing operand A = 10\n");
    apb_write(MULT_OPERAND_A, 10);
    
    printf("SUCCESS! Write completed\n");  // If we see this, write worked
    
    // ... rest of your tests

    
    // Test 1: Basic multiplication
    printf("Test 1: 10 * 20 = ");
    apb_write(MULT_OPERAND_A, 10);
    apb_write(MULT_OPERAND_B, 20);
    apb_write(MULT_CONTROL, 1);  // Start
    
    delay(100);  // Wait for computation
    
    uint32_t result = apb_read(MULT_RESULT_LO);
    printf("%d ", result);
    
    if (result == 200) {
        printf("PASS\n");
    } else {
        printf("FAIL (expected 200)\n");
    }
    
    // Test 2: Zero multiplication
    printf("Test 2: 0 * 999 = ");
    apb_write(MULT_OPERAND_A, 0);
    apb_write(MULT_OPERAND_B, 999);
    apb_write(MULT_CONTROL, 1);
    
    delay(100);
    
    result = apb_read(MULT_RESULT_LO);
    printf("%d ", result);
    
    if (result == 0) {
        printf("PASS\n");
    } else {
        printf("FAIL (expected 0)\n");
    }
    
    // Test 3: Large multiplication (tests 64-bit result)
    printf("Test 3: 65535 * 65535 = ");
    apb_write(MULT_OPERAND_A, 65535);
    apb_write(MULT_OPERAND_B, 65535);
    apb_write(MULT_CONTROL, 1);
    
    delay(100);
    
    uint32_t result_lo = apb_read(MULT_RESULT_LO);
    uint32_t result_hi = apb_read(MULT_RESULT_HI);
    printf("0x%08x%08x ", result_hi, result_lo);
    
    if (result_lo == 0xFFFE0001 && result_hi == 0) {
        printf("PASS\n");
    } else {
        printf("FAIL (expected 0x00000000FFFE0001)\n");
    }
    
    // Test 4: Register readback
    printf("Test 4: Register readback - ");
    apb_write(MULT_OPERAND_A, 0x12345678);
    apb_write(MULT_OPERAND_B, 0xABCDEF00);
    
    uint32_t read_a = apb_read(MULT_OPERAND_A);
    uint32_t read_b = apb_read(MULT_OPERAND_B);
    
    if (read_a == 0x12345678 && read_b == 0xABCDEF00) {
        printf("PASS\n");
    } else {
        printf("FAIL (got 0x%08x, 0x%08x)\n", read_a, read_b);
    }
    
    // Test 5: Status register
    printf("Test 5: Status register - ");
    uint32_t status = apb_read(MULT_STATUS);
    printf("ops=%d ", status);
    
    if (status >= 3) {  // At least 3 operations completed
        printf("PASS\n");
    } else {
        printf("FAIL\n");
    }
    
    printf("\n=================================\n");
    printf("APB Multiplier Test Complete\n");
    printf("=================================\n\n");
    
    return 0;
}