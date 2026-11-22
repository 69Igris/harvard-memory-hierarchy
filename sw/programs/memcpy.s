# memcpy.s - copy a 64-word block, word by word (streaming workload)
# One load + one store per 6-instruction iteration; perfectly sequential
# addresses, so data caches benefit from spatial locality (line refills) and
# the write buffer is exercised by back-to-back stores.
.text
        la   s0, src
        la   s1, dst
        li   s2, 64
        li   t0, 0
copy:   lw   t1, 0(s0)
        sw   t1, 0(s1)
        addi s0, s0, 4
        addi s1, s1, 4
        addi t0, t0, 1
        blt  t0, s2, copy
        halt
.data
src:    .word -49, -12, 25, 62, 99, 136, -27, 10
        .word 47, 84, 121, -42, -5, 32, 69, 106
        .word -57, -20, 17, 54, 91, 128, -35, 2
        .word 39, 76, 113, -50, -13, 24, 61, 98
        .word 135, -28, 9, 46, 83, 120, -43, -6
        .word 31, 68, 105, -58, -21, 16, 53, 90
        .word 127, -36, 1, 38, 75, 112, -51, -14
        .word 23, 60, 97, 134, -29, 8, 45, 82
dst:    .space 256
