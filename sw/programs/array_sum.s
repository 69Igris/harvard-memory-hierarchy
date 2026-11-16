# array_sum.s - sum 32 words of an array in data memory
# Memory-moderate workload: 1 load per loop iteration.
.text
        la   s0, array          # s0 = &array[0]   (0x1000)
        li   s1, 32             # s1 = N
        li   t0, 0              # t0 = i
        li   a0, 0              # a0 = sum
loop:   lw   t1, 0(s0)          # t1 = array[i]
        add  a0, a0, t1         # sum += array[i]
        addi s0, s0, 4
        addi t0, t0, 1
        blt  t0, s1, loop
        la   t2, result
        sw   a0, 0(t2)          # result = sum
        li   t3, 0x2000
        sw   a0, 0(t3)          # OUT <- sum
        halt
.data
array:  .word 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16
        .word 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
result: .word 0
