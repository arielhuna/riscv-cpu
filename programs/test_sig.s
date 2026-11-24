# test_sig.s - signature test: every result is stored to the signature area
# signature: 8 words at 0x200 (dmem word 128); tohost = 0x3FC (word 255)
        addi s0, x0, 0x200      # s0 = signature base
        addi t0, x0, 5
        addi t1, x0, -3
        add  t2, t0, t1         # 5 + (-3) = 2
        sw   t2, 0(s0)
        sub  t2, t0, t1         # 5 - (-3) = 8
        sw   t2, 4(s0)
        slt  t2, t1, t0         # -3 < 5 signed = 1
        sw   t2, 8(s0)
        sltu t2, t1, t0         # 0xFFFFFFFD < 5 unsigned = 0
        sw   t2, 12(s0)
        lui  t2, 0x12345        # 0x12345000
        sw   t2, 16(s0)
        sw   t1, 20(s0)         # word FFFFFFFD
        lb   t2, 20(s0)         # byte FD sign-extended = FFFFFFFD
        lbu  t3, 20(s0)         # byte FD zero-extended = 000000FD
        add  t2, t2, t3         # FFFFFFFD + FD = 000000FA
        sw   t2, 24(s0)
        jal  ra, func           # ra = return address
        sw   ra, 28(s0)
        addi t4, x0, 1
        sw   t4, 1020(x0)       # tohost = 1: test finished
done:   jal  x0, done
func:   jalr x0, 0(ra)