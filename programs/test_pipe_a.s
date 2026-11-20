# Lesson 26a: pipeline cards (IF/ID, ID/EX) and EX, no register writes yet
        addi  t0, x0, 5        # 0x00
        addi  t1, x0, -3       # 0x04
        lui   t2, 0x12345      # 0x08
        auipc t3, 1            # 0x0C
done:   jal   x0, done         # 0x10
        nop                    # 0x14  fetched behind the jump
        nop                    # 0x18
