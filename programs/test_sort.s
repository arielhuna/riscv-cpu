# test_sort: bubble sort of a[4] = {5, -3, 9, 0} at address 0

# --- main: build the array in dmem ---
        ADDI  t0, x0, 5
        SW    t0, 0(x0)       # a[0] = 5
        ADDI  t0, x0, -3      # a[1] = -3
        SW    t0, 4(x0)       
        ADDI  t0, x0, 9       # a[2] = 9
        SW    t0, 8(x0)
        SW    x0, 0xC(x0)     # a[3] = 0 (x0 is always zero)

# --- call sort(a, 4) ---
        ADDI  a0, x0, 0       # a0 = base address of a[]
        ADDI  a1, x0, 4       # a1 = n
        JAL   ra, sort
done:   JAL   x0, done


# --- sort(p = a0, n = a1) ---
sort:   ADDI  t1, a1, -1       # t1 = n - 1
        ADDI  t0, x0, 0       # pass = 0
outer:  BGE   t0, t1, end_sort   # if pass >= n-1: exit loop

        ADDI  t2, x0, 0       # j = 0
        ADDI  t3, a0, 0       # t3 = &p[0]
inner:  BGE   t2, t1, inner_end  # if j >= n-1: exit inner loop

        LW    t4, 0(t3)       # t4 = p[j]
        LW    t5, 4(t3)       # t5 = p[j+1]
        BGE  t5, t4, no_swap    # if p[j+1] >= p[j]: already in order
        SW    t5, 0(t3)        # p[j]   = p[j+1]
        SW    t4, 4(t3)        # p[j+1] = old p[j]
no_swap:

        ADDI  t2, t2, 1       # j++
        ADDI  t3, t3, 4       # t3 = &p[j+1]: next word
        JAL   x0, inner
inner_end:

        ADDI  t0, t0, 1       # pass++
        JAL   x0, outer          # back to the top
end_sort:
        JALR  x0, 0(ra)          # return to caller