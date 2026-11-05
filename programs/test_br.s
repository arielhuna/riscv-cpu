# test_br: BLT/BLTU/BGE/BGEU, LUI, AUIPC
# x1 = -1 (FFFFFFFF), x2 = 8: signed and unsigned answers differ
        ADDI  x1, x0, -1
        ADDI  x2, x0, 8

        BLT   x1, x2, t1        # -1 < 8 signed
        ADDI  x10, x0, 1        # marker: runs only if BLT not taken
t1:     BLTU  x1, x2, t2        # FFFFFFFF < 8 unsigned
        ADDI  x11, x0, 1        # marker: runs only if BLTU not taken
t2:     BGE   x1, x2, t3        # -1 >= 8 signed
        ADDI  x12, x0, 1        # marker: runs only if BGE not taken
t3:     BGEU  x1, x2, t4        # FFFFFFFF >= 8 unsigned
        ADDI  x13, x0, 1        # marker: runs only if BGEU not taken

t4:     LUI   x5, 0x12345
        AUIPC x6, 0x1

done:   JAL   x0, done