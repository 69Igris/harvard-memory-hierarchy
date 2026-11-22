# unrolled_sum.s - sum a 64-word array with a FULLY UNROLLED loop body,
# repeated 4 times. The body is 128 instructions (512 B of code), larger than
# a 256 B instruction cache, so this program stresses the INSTRUCTION side of
# the hierarchy (capacity misses) while its data fits easily.
.text
        li   s2, 4              # repeat count
        li   s3, 0              # total
again:  la   s0, arr
        li   s1, 0
        lw   t1, 0(s0)
        add  s1, s1, t1
        lw   t1, 4(s0)
        add  s1, s1, t1
        lw   t1, 8(s0)
        add  s1, s1, t1
        lw   t1, 12(s0)
        add  s1, s1, t1
        lw   t1, 16(s0)
        add  s1, s1, t1
        lw   t1, 20(s0)
        add  s1, s1, t1
        lw   t1, 24(s0)
        add  s1, s1, t1
        lw   t1, 28(s0)
        add  s1, s1, t1
        lw   t1, 32(s0)
        add  s1, s1, t1
        lw   t1, 36(s0)
        add  s1, s1, t1
        lw   t1, 40(s0)
        add  s1, s1, t1
        lw   t1, 44(s0)
        add  s1, s1, t1
        lw   t1, 48(s0)
        add  s1, s1, t1
        lw   t1, 52(s0)
        add  s1, s1, t1
        lw   t1, 56(s0)
        add  s1, s1, t1
        lw   t1, 60(s0)
        add  s1, s1, t1
        lw   t1, 64(s0)
        add  s1, s1, t1
        lw   t1, 68(s0)
        add  s1, s1, t1
        lw   t1, 72(s0)
        add  s1, s1, t1
        lw   t1, 76(s0)
        add  s1, s1, t1
        lw   t1, 80(s0)
        add  s1, s1, t1
        lw   t1, 84(s0)
        add  s1, s1, t1
        lw   t1, 88(s0)
        add  s1, s1, t1
        lw   t1, 92(s0)
        add  s1, s1, t1
        lw   t1, 96(s0)
        add  s1, s1, t1
        lw   t1, 100(s0)
        add  s1, s1, t1
        lw   t1, 104(s0)
        add  s1, s1, t1
        lw   t1, 108(s0)
        add  s1, s1, t1
        lw   t1, 112(s0)
        add  s1, s1, t1
        lw   t1, 116(s0)
        add  s1, s1, t1
        lw   t1, 120(s0)
        add  s1, s1, t1
        lw   t1, 124(s0)
        add  s1, s1, t1
        lw   t1, 128(s0)
        add  s1, s1, t1
        lw   t1, 132(s0)
        add  s1, s1, t1
        lw   t1, 136(s0)
        add  s1, s1, t1
        lw   t1, 140(s0)
        add  s1, s1, t1
        lw   t1, 144(s0)
        add  s1, s1, t1
        lw   t1, 148(s0)
        add  s1, s1, t1
        lw   t1, 152(s0)
        add  s1, s1, t1
        lw   t1, 156(s0)
        add  s1, s1, t1
        lw   t1, 160(s0)
        add  s1, s1, t1
        lw   t1, 164(s0)
        add  s1, s1, t1
        lw   t1, 168(s0)
        add  s1, s1, t1
        lw   t1, 172(s0)
        add  s1, s1, t1
        lw   t1, 176(s0)
        add  s1, s1, t1
        lw   t1, 180(s0)
        add  s1, s1, t1
        lw   t1, 184(s0)
        add  s1, s1, t1
        lw   t1, 188(s0)
        add  s1, s1, t1
        lw   t1, 192(s0)
        add  s1, s1, t1
        lw   t1, 196(s0)
        add  s1, s1, t1
        lw   t1, 200(s0)
        add  s1, s1, t1
        lw   t1, 204(s0)
        add  s1, s1, t1
        lw   t1, 208(s0)
        add  s1, s1, t1
        lw   t1, 212(s0)
        add  s1, s1, t1
        lw   t1, 216(s0)
        add  s1, s1, t1
        lw   t1, 220(s0)
        add  s1, s1, t1
        lw   t1, 224(s0)
        add  s1, s1, t1
        lw   t1, 228(s0)
        add  s1, s1, t1
        lw   t1, 232(s0)
        add  s1, s1, t1
        lw   t1, 236(s0)
        add  s1, s1, t1
        lw   t1, 240(s0)
        add  s1, s1, t1
        lw   t1, 244(s0)
        add  s1, s1, t1
        lw   t1, 248(s0)
        add  s1, s1, t1
        lw   t1, 252(s0)
        add  s1, s1, t1
        add  s3, s3, s1
        addi s2, s2, -1
        bne  s2, x0, again
        la   t0, result
        sw   s3, 0(t0)
        halt
.data
arr:    .word 5, 18, 31, 44, 57, 70, 83, 96
        .word 12, 25, 38, 51, 64, 77, 90, 6
        .word 19, 32, 45, 58, 71, 84, 0, 13
        .word 26, 39, 52, 65, 78, 91, 7, 20
        .word 33, 46, 59, 72, 85, 1, 14, 27
        .word 40, 53, 66, 79, 92, 8, 21, 34
        .word 47, 60, 73, 86, 2, 15, 28, 41
        .word 54, 67, 80, 93, 9, 22, 35, 48
result: .word 0
