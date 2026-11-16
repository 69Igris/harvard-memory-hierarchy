# fibonacci.s - compute fib(0..24) in registers, store only fib(24)
# Compute-bound workload: almost no data-memory traffic.
.text
        li   t0, 0              # f(n-2)
        li   t1, 1              # f(n-1)
        li   t2, 1              # n
        li   t3, 24
loop:   add  t4, t0, t1
        mv   t0, t1
        mv   t1, t4
        addi t2, t2, 1
        blt  t2, t3, loop
        la   s0, fib
        sw   t1, 0(s0)
        halt
.data
fib:    .word 0
