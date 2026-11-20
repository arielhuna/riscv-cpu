# --- build mem[4] = 0x7EF09285 byte by byte (tests SB + st_be) ---
ADDI x5, x0, -123     # 0xFFFFFF85
ADDI x6, x0, -110     # 0xFFFFFF92
ADDI x7, x0, -16      # 0xFFFFFFF0
ADDI x8, x0, 126      # 0x0000007E
SB   x5, 16(x0)
SB   x6, 17(x0)
SB   x7, 18(x0)
SB   x8, 19(x0)

# --- read it back every way (tests ld_byte, ld_half, extension) ---
LB   x10, 16(x0)      # FFFFFF85
LBU  x11, 16(x0)      # 00000085
LH   x12, 16(x0)      # FFFF9285
LHU  x13, 16(x0)      # 00009285
LH   x14, 18(x0)      # 00007EF0
LB   x15, 19(x0)      # 0000007E

# --- SH into the upper half, lower half must survive ---
SH   x5, 18(x0)       # mem[4] = FF859285
