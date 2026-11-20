        ADDI x10, x0, 5       # 0x00: argument = 5
        JAL  x1, func         # 0x04: call func, x1 = return address
        ADDI x12, x10, 0      # 0x08: copy result
done:   JAL  x0, done         # 0x0C: halt
        ADDI x13, x0, 99      # 0x10: must NEVER run
func:   ADD  x10, x10, x10    # 0x14: x10 = x10 * 2
        JALR x0, 0(x1)        # 0x18: return
