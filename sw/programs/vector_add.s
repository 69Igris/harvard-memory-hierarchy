# vector_add.s - C[i] = A[i] + B[i], i = 0..15
# Memory-heavy workload: 2 loads + 1 store per iteration.
.text
        la   s0, vecA
        la   s1, vecB
        la   s2, vecC
        li   s3, 16
        li   t0, 0
loop:   lw   t1, 0(s0)
        lw   t2, 0(s1)
        add  t3, t1, t2
        sw   t3, 0(s2)
        addi s0, s0, 4
        addi s1, s1, 4
        addi s2, s2, 4
        addi t0, t0, 1
        bne  t0, s3, loop
        halt
.data
vecA:   .word 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160
vecB:   .word 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31
vecC:   .space 64
