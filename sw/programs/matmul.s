# matmul.s - 4x4 integer matrix multiply C = A x B
# No MUL instruction in our subset, so a shift-and-add subroutine is called
# through JAL/JALR. Mixed workload: nested loops, function calls, 2 loads per
# inner iteration, 16 stores.
.text
        la   s0, A
        la   s1, B
        la   s2, C
        li   s3, 4              # N
        li   t0, 0              # i
loop_i: li   t1, 0              # j
loop_j: li   s4, 0              # acc
        li   t2, 0              # k
loop_k: slli t3, t0, 2          # &A[i][k] = A + (4i + k)*4
        add  t3, t3, t2
        slli t3, t3, 2
        add  t3, t3, s0
        lw   a0, 0(t3)
        slli t4, t2, 2          # &B[k][j] = B + (4k + j)*4
        add  t4, t4, t1
        slli t4, t4, 2
        add  t4, t4, s1
        lw   a1, 0(t4)
        jal  ra, mul
        add  s4, s4, a2
        addi t2, t2, 1
        blt  t2, s3, loop_k
        slli t3, t0, 2          # C[i][j] = acc
        add  t3, t3, t1
        slli t3, t3, 2
        add  t3, t3, s2
        sw   s4, 0(t3)
        addi t1, t1, 1
        blt  t1, s3, loop_j
        addi t0, t0, 1
        blt  t0, s3, loop_i
        halt

# a2 = a0 * a1  (shift-and-add, a1 >= 0)
mul:    li   a2, 0
        mv   a3, a0
        mv   a4, a1
mul_lp: beq  a4, x0, mul_dn
        andi a5, a4, 1
        beq  a5, x0, mul_sk
        add  a2, a2, a3
mul_sk: slli a3, a3, 1
        srli a4, a4, 1
        j    mul_lp
mul_dn: jalr x0, 0(ra)

.data
A:      .word 3, -1, 4, 1,   5, 9, -2, 6,   5, 3, 5, -8,   9, 7, 9, 3
B:      .word 2, 7, 1, 8,    2, 8, 1, 8,    2, 8, 4, 5,    9, 0, 4, 5
C:      .space 64
