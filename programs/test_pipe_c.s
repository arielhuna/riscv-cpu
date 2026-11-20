# Lesson 27: forwarding (EX/MEM, MEM/WB) + WB->ID bypass.
# Data hazards are NOT avoided with NOPs anymore. Still required (until 28-29):
#   - no load immediately followed by a use of its rd (load-use, lesson 28)
#   - 2 NOPs after every jump / taken branch (no flush yet, lesson 29)
        addi  t0, x0, 5        # 0x00  t0 = 5
        addi  t1, x0, -3       # 0x04  t1 = -3
        add   t2, t0, t1       # 0x08  t2 = 2     t0 from WB, t1 from MEM
        addi  s0, x0, 1        # 0x0C  s0 = 1
        addi  s0, x0, 2        # 0x10  s0 = 2     (newer write)
        add   s1, s0, s0       # 0x14  s1 = 4     MEM must win over WB
        addi  a0, x0, 7        # 0x18  a0 = 7
        nop                    # 0x1C
        nop                    # 0x20
        add   a1, a0, a0       # 0x24  a1 = 14    WB->ID bypass
        addi  a3, x0, 99       # 0x28  a3 = 99
        sw    a3, 64(x0)       # 0x2C  mem[16] = 99   store data forwarded
        lw    a4, 64(x0)       # 0x30  a4 = 99
        addi  s2, x0, 1        # 0x34  s2 = 1     (gap of 1 after the load)
        add   a5, a4, s2       # 0x38  a5 = 100   a4 from WB (wb_data = ld_data), s2 from MEM
        addi  x0, x0, 9        # 0x3C  x0 stays 0
        add   t6, x0, x0       # 0x40  t6 = 0     never forward to x0
        addi  t3, x0, -1       # 0x44  t3 = -1
        blt   t3, x0, skip     # 0x48  taken: compare uses forwarded t3
        nop                    # 0x4C  runs behind the branch
        nop                    # 0x50
        addi  t4, x0, 55       # 0x54  must NEVER run
skip:   addi  t5, x0, 1        # 0x58  t5 = 1
done:   jal   x0, done         # 0x5C
        nop                    # 0x60
        nop                    # 0x64
