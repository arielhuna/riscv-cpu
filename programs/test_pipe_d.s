# Lesson 28: load-use stall.
# A load is now allowed to be followed IMMEDIATELY by a use of its rd:
# the hazard unit stalls 1 cycle, then MEM/WB forwarding delivers the value.
# Still required (until 29): 2 NOPs after every jump / taken branch.
        addi  a3, x0, 99       # 0x00  a3 = 99
        sw    a3, 64(x0)       # 0x04  mem[16] = 99
        addi  s2, x0, 1        # 0x08  s2 = 1
        lw    a4, 64(x0)       # 0x0C  a4 = 99
        add   a5, a4, s2       # 0x10  a5 = 100   load-use on rs1 (ALU)  -> stall
        lw    a6, 64(x0)       # 0x14  a6 = 99
        sw    a6, 68(x0)       # 0x18  mem[17] = 99  load-use on rs2 (store data) -> stall
        addi  t3, x0, -1       # 0x1C  t3 = -1
        sw    t3, 72(x0)       # 0x20  mem[18] = -1
        lw    t4, 72(x0)       # 0x24  t4 = -1
        blt   t4, x0, skip     # 0x28  load-use on compare -> stall, then taken
        nop                    # 0x2C  runs behind the branch
        nop                    # 0x30
        addi  t5, x0, 55       # 0x34  must NEVER run
skip:   lw    s3, 64(x0)       # 0x38  s3 = 99
        add   s4, s3, s3       # 0x3C  s4 = 198   rs1 AND rs2 both need the load -> one stall
done:   jal   x0, done         # 0x40
        nop                    # 0x44
        nop                    # 0x48