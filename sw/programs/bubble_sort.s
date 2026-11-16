# bubble_sort.s - in-place bubble sort of 12 words (ascending)
# Memory-heavy + branch-heavy workload.
.text
        la   s0, arr
        li   s1, 12             # n
        li   t0, 0              # i
outer:  li   t1, 0              # j
        sub  t5, s1, t0
        addi t5, t5, -1         # limit = n - i - 1
        mv   t6, s0             # p = &arr[0]
inner:  bge  t1, t5, next_i
        lw   t2, 0(t6)
        lw   t3, 4(t6)
        bge  t3, t2, noswap     # if arr[j+1] >= arr[j] skip
        sw   t3, 0(t6)
        sw   t2, 4(t6)
noswap: addi t6, t6, 4
        addi t1, t1, 1
        j    inner
next_i: addi t0, t0, 1
        addi t4, s1, -1
        blt  t0, t4, outer
        halt
.data
arr:    .word 42, -7, 19, 3, 88, 0, 25, -15, 61, 7, 33, 12
