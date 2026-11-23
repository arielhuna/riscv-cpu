# Lesson 29: flush.
# No NOPs after jumps / taken branches any more: the hardware kills
# the 2 wrong-path instructions (IF and ID) when EX redirects the PC.
# "must never run" = only reachable on the wrong path.
        addi  t0, x0, 5        # 0x00  t0 = 5
        addi  t1, x0, 5        # 0x04  t1 = 5
        add   s3, x0, x0       # 0x08  s3 = 0 (run counter)
        sw    t0, 64(x0)       # 0x0C  mem[16] = 5
        beq   t0, t1, l1       # 0x10  taken -> flush #1
        addi  s0, x0, 99       # 0x14  must never run (was in ID)
        jal   x0, bad          # 0x18  must never run (was in IF): a wrong-path jump
l1:     addi  s1, x0, 1        # 0x1C  s1 = 1
        bne   t0, t1, bad      # 0x20  NOT taken -> no flush
        addi  s2, x0, 2        # 0x24  s2 = 2 (must run)
        jal   ra, func         # 0x28  ra = 0x2C -> flush #2
        addi  s3, s3, 1        # 0x2C  runs exactly once (after ret): s3 = 1
        bnez  s1, done         # 0x30  taken -> flush #5
        addi  s4, x0, 99       # 0x34  must never run
        addi  s5, x0, 99       # 0x38  must never run
done:   jal   x0, done         # 0x3C  (its flushes are not counted)
func:   lw    a2, 64(x0)       # 0x40  a2 = 5
        beq   a2, t0, ok       # 0x44  load-use: stall 1, then taken -> flush #3
        addi  s6, x0, 99       # 0x48  must never run
        addi  s7, x0, 99       # 0x4C  must never run
ok:     ret                    # 0x50  back to 0x2C -> flush #4
        addi  s8, x0, 99       # 0x54  must never run
        addi  s9, x0, 99       # 0x58  must never run
bad:    addi  s10, x0, 99      # 0x5C  must never run
        jal   x0, bad          # 0x60