# Lesson 26b: full 5-stage pipeline, NO hazard handling yet.
# Rules for this program (until lessons 27-29):
#   - 3 instructions between a write to a register and its read (no forwarding, no regfile bypass)
#   - 2 NOPs after every jump / taken branch (no flush: they run anyway)
        addi  t0, x0, 5        # 0x00  t0 = 5
        addi  t1, x0, -3       # 0x04  t1 = -3
        addi  a0, x0, 64       # 0x08  a0 = 64 (data base address)
        nop                    # 0x0C
        nop                    # 0x10
        add   t2, t0, t1       # 0x14  t2 = 2     (t1 written 4 instructions earlier)
        sw    t0, 0(a0)        # 0x18  mem[16] = 5
        sb    t1, 4(a0)        # 0x1C  mem[17] byte 0 = FD
        lw    s0, 0(a0)        # 0x20  s0 = 5
        lb    s1, 4(a0)        # 0x24  s1 = FFFFFFFD
        lbu   s2, 4(a0)        # 0x28  s2 = 000000FD
        lui   s3, 0x12345      # 0x2C  s3 = 12345000
        jal   ra, func         # 0x30  ra = 0x34
        nop                    # 0x34  runs behind the jump (and again after ret)
        nop                    # 0x38
        beq   t0, t0, skip     # 0x3C  always taken
        nop                    # 0x40  runs behind the branch
        nop                    # 0x44
        addi  s4, x0, 99       # 0x48  must NEVER run
skip:   addi  s4, x0, 1        # 0x4C  s4 = 1
done:   jal   x0, done         # 0x50
        nop                    # 0x54
        nop                    # 0x58
func:   addi  a1, x0, 7        # 0x5C  a1 = 7  (gives ra 3 instructions to reach WB)
        ret                    # 0x60  back to 0x34
        nop                    # 0x64  runs behind ret
        nop                    # 0x68