// Minimal test environment for riscv-cpu (no CSRs, no traps).
// Pass: tohost (0x3FC) = 1. Fail: tohost = (test number << 1) | 1.
#ifndef _ENV_RISCV_CPU_H
#define _ENV_RISCV_CPU_H

#define RVTEST_RV32U
#define RVTEST_RV64U
#define TESTNUM gp

#define RVTEST_CODE_BEGIN       \
        .text;                  \
        .globl _start;          \
_start:

#define RVTEST_CODE_END

#define RVTEST_PASS             \
        li   a0, 1;             \
        sw   a0, 0x3FC(x0);     \
1:      j    1b;

#define RVTEST_FAIL             \
        slli a0, TESTNUM, 1;    \
        ori  a0, a0, 1;         \
        sw   a0, 0x3FC(x0);     \
1:      j    1b;

#define RVTEST_DATA_BEGIN       \
        .data;                  \
        .align 4;

#define RVTEST_DATA_END

#endif
