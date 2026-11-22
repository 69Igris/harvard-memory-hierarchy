# The whole project, explained simply

This guide explains what we built, why, and how every part works, in plain language. Read it
top to bottom once. After that, use it as a reference before the viva.

> **The project in one line:** a CPU must read instructions *and* read/write data. We built two
> ways of connecting the CPU to memory (one shared memory vs separate memories), then a
> realistic version with caches. We measured how fast each one is, cycle by cycle.

---

## 1. The basic idea (no jargon)

### 1.1 What a CPU does with memory
A program is a list of instructions stored in memory. To run one instruction, the CPU:

1. **Fetches** the instruction: reads it from memory at the address held in the **PC** (program
   counter). This happens for **every** instruction.
2. **Executes** it: adds numbers, compares, jumps, and so on.
3. If the instruction is a **load** (`lw`) or **store** (`sw`), it also **reads or writes data**
   in memory.

So a load or store needs memory **twice**: once to fetch the instruction and once for the data.

### 1.2 The shop analogy
Think of memory as a shop with a counter.

- **Von Neumann** = one shop, one counter. Instructions and data are sold at the same counter.
  If you need both at once, one has to wait in line.
- **Harvard** = two shops side by side: one sells only instructions, the other only data. You
  can buy from both at the same moment.

Waiting in line is called a **stall**. The reason for the wait (two users, one counter) is
called a **structural hazard**.

### 1.3 What "cycle" and "CPI" mean
- The CPU works in steps called **clock cycles**. Our core is **single-cycle**: if nothing
  waits, one instruction finishes every cycle.
- **CPI** = **C**ycles **P**er **I**nstruction = total cycles ÷ instructions run.
  CPI = 1.00 is perfect for our core. Higher is slower.

---

## 2. Phase I: Harvard vs Von Neumann (already submitted)

### 2.1 What we built
One small processor (a **core**) that runs a subset of the RISC-V instruction set (RV32I). We
used the **same core, unchanged**, in two complete systems, so the only difference is the
memory:

| System | File | Memory |
|---|---|---|
| Harvard | `rtl/harvard_top.v` | `imem.v` for code + `dmem.v` for data, both usable in the same cycle |
| Von Neumann | `rtl/vonneumann_top.v` | one `unified_mem.v` holding code and data, with an arbiter that decides who uses it |

### 2.2 The core's parts (files in `rtl/`)
| File | What it does, simply |
|---|---|
| `pc.v` | Holds the address of the next instruction. Adds 4 each cycle, or jumps. |
| `regfile.v` | 32 small storage boxes (x0–x31) inside the CPU. x0 is always 0. |
| `alu.v` | The calculator: add, subtract, AND, OR, shifts, compares. |
| `imm_gen.v` | Pulls the constant number (the "immediate") out of the instruction bits. |
| `control_unit.v` | Reads the instruction type and switches the right signals on (write register? read memory? branch?). |
| `cpu_core.v` | Wires all of the above together. Has a `stall` input: when it is 1, the core freezes (PC and registers do not change). |

### 2.3 The data side
| File | What it does |
|---|---|
| `addr_decoder.v` | Looks at the top bits of an address and decides where it goes: data memory, I/O, or "bus error" (invalid). |
| `rw_control.v` | Turns "load" / "store" into the actual read and write-enable signals. |
| `dmem.v` | The data memory. |
| `io_regs.v` | A few special addresses. Writing to one of them means "program finished" (HALT). |

### 2.4 How Von Neumann loses time
Program `addi, lw, add, sw, addi`:

- **Harvard:** 5 instructions → **5 cycles**. `lw` fetches and reads data in the same cycle.
- **Von Neumann:** `lw` and `sw` each need the single memory twice → **7 cycles**.

In general: **CPI(Von Neumann) = 1 + f_mem**, where f_mem is the fraction of instructions that
are loads or stores. Harvard CPI is always **1.00**.

### 2.5 Phase I results
| Program | Loads+stores | Speed-up of Harvard |
|---|---:|---:|
| fibonacci | 1.6 % | 1.02× |
| matmul | 5.6 % | 1.06× |
| array_sum | 19.9 % | 1.20× |
| bubble_sort | 31.1 % | 1.31× |
| vector_add | 31.4 % | 1.31× |
| memcpy | 32.7 % | 1.33× |
| unrolled_sum | 47.0 % | 1.47× |

The speed-up is **exactly** 1 + f_mem in every case. The hardware stall counter equals the
number of loads + stores.

---

## 3. Phase II: the realistic version

### 3.1 The problem: real memory is slow
In Phase I, memory answered instantly. Real main memory (DRAM) takes many cycles. We added the
brief's **"optional shared lower-level memory"**: `main_mem.v`, one 8 KB memory that holds
**both** code and data and takes **LAT** cycles to answer (we tested LAT = 1, 2, 4, 8, 16).

With slow memory and **no cache**, CPI becomes about **12** at LAT = 8. Splitting the paths
(Harvard-style ports) only improves that from **12.28 to 12.01**, about 2 %. Both paths still end
at the same slow memory, so they still take turns.

> **Key insight:** two roads only help if each road has something **private and fast** on it.
> That fast private thing is a **cache**.

### 3.2 What a cache is
A **cache** is a small, fast memory next to the CPU that keeps copies of recently used data.

- **Hit:** the data is in the cache → answered in the same cycle, no waiting.
- **Miss:** the data is not there → fetch it from slow main memory and wait.

Analogy: your desk (cache) vs the library (main memory). Books on your desk are instant. For
anything else you walk to the library, so you bring back a few books on the same shelf (a
**line**) in case you need them next.

### 3.3 How our cache finds data (`rtl/l1_cache.v`)
Our cache is **direct-mapped**: each address can live in exactly **one** place (one "set").
The address is split into three parts:

```
word = address / 4
offset = word % LINE_WORDS              -> which word inside the line
index  = (word / LINE_WORDS) % SETS     -> which set (row) of the cache
tag    = word / (LINE_WORDS * SETS)     -> "name tag" to check it's the right line
```

The cache looks at row `index`. If that row is **valid** and its stored **tag** equals the
address's tag, it is a **hit**. Otherwise it is a **miss**.

On a miss the cache asks main memory for the **whole line** (4 words) as one **burst**. Memory
needs LAT cycles for the first word, then sends one word per cycle. So:

> **Miss penalty = LAT + words per line** (for example 4 + 4 = 8 cycles).

### 3.4 How stores work: write-through + write buffer
- **Write-through:** every store is also written to main memory, so memory is always up to date.
- **No-write-allocate:** a store that misses does **not** bring the line into the cache.
- **1-entry write buffer:** the store is parked in a small buffer and finishes in **1 cycle**.
  The buffer is written to memory **in the background** while the CPU keeps running.
  - A second store right behind the first must wait until the buffer is empty (LAT + 1 cycles).
  - A read miss also waits for the buffer to empty first, so it never reads old data
    (this is called **RAW safety**: read-after-write).

### 3.5 The four designs we compare
All use the same core and the same main memory. The two cached designs have the **same total cache size** (512 B: 256 B + 256 B split, or 512 B unified).

| Name | Plain meaning | Colour in charts |
|---|---|---|
| `vn_flat` | Von Neumann, no cache | orange |
| `split_flat` | Harvard ports, no cache | green |
| `unified` | one cache for code + data together | yellow |
| `split` (**ours**) | separate instruction cache + data cache, over one shared memory = **Modified Harvard** | blue |

### 3.6 The proposed design: Modified Harvard (`rtl/modharvard_top.v`)
```
            +---------+        +----------+
 cpu_core --| I-cache |--+     |          |
    |       +---------+  +---->| arbiter  |----> main_mem (8 KB, slow, code+data)
    |       +---------+  +---->|          |
    +-------| D-cache |--+     +----------+
            +---------+
```
- **Top half is Harvard:** the core reads from the I-cache and the D-cache **in the same
  cycle**. When both hit, nothing waits.
- **Bottom half is Von Neumann:** one shared main memory. The **arbiter** (`mem_arbiter.v`)
  only gets requests when a cache **misses**. If both miss at once, the instruction side goes
  first, because the core can't do anything without its instruction.
- The core freezes when any of these is true:
  `core_stall = halted | i_stall | d_stall | io_wait`.
- **This is how real processors (ARM, x86, RISC-V) are built:** split L1 caches over a
  unified memory.

### 3.7 The comparison design: one unified cache (`rtl/unicache_top.v`)
One cache holds both code and data. It has only **one port**, so a load/store still needs a
second cycle: the same structural hazard as Phase I Von Neumann. It also suffers **conflict
misses**:

- Code starts at address `0x0000` and data at `0x1000` (4096).
- 4096 is a multiple of the cache size, so the first code line and the first data line map to
  the **same set**. They keep throwing each other out.
- Example: matmul's data miss rate is **55 % unified vs 6 % split**.

### 3.8 Phase II results (LAT = 8, geo-mean of 7 programs)
| Design | CPI | What it means |
|---|---:|---|
| VN, no cache | 12.28 | very slow |
| Harvard ports, no cache | 12.01 | splitting alone barely helps |
| Unified L1 | 2.81 | caches help a lot |
| **Split L1 (ours)** | **2.01** | best |

- Split L1 is **1.40× faster** than a unified cache of the same size and **6.1× faster** than no
  cache.
- Read miss rate: **4.0 % vs 8.9 %**.
- **AMAT** (average memory access time) = 1 + miss rate × (LAT + 4) = **1.64 vs 2.15 cycles**.
- As memory gets slower the gap **grows**: at LAT = 16, CPI is 2.85 vs 4.05.
- Split wins on **every** program (1.02× to 1.87×).
- When is unified better? Only for the instruction side of `unrolled_sum`, whose 512 B loop is
  bigger than the 256 B I-cache. Split still wins overall (1.11×).

### 3.9 Hardware cost (synthesis with Yosys, Xilinx target)
| Design | LUTs | Flip-flops |
|---|---:|---:|
| Harvard (Phase I) | 874 | 129 |
| Von Neumann (Phase I) | 1210 | 162 |
| Split L1 | 1676 | 303 |
| Unified L1 | 1770 | 315 |

Split L1 is faster **and** about 5 % smaller. We do **not** claim a maximum clock frequency,
because that needs place-and-route on a real FPGA.

---

## 4. The files in Phase II

| File | Owner | What it does |
|---|---|---|
| `rtl/main_mem.v` | Himank | Slow shared memory. Request accepted at cycle t, first word at t + LAT, then one word per cycle. |
| `rtl/mem_arbiter.v` | Himank | Lets one cache at a time use main memory; I-side has priority. Remembers who owns the transfer so the data goes back to the right cache. |
| `rtl/l1_cache.v` | Shivam | The cache. One design used three ways: I-cache (read-only), D-cache, unified. Has the write buffer and a `NOCACHE` mode used for the "flat" designs. |
| `rtl/modharvard_top.v` | Aaryan | Proposed system: core + I-cache + D-cache + arbiter + main memory + I/O + counters. |
| `rtl/unicache_top.v` | Himank | Comparison system with one unified cache. |
| `rtl/hier_perf.v` | Himank | Counters: cycles, instructions, hits, misses, and the reason for each stall cycle. |
| `rtl/cpu_core.v` (edit) | Aaryan | Added `d_wreq`, a store request that is not blocked by `stall`. Without it the cache would use a signal that depends on its own output (a loop). |
| `sw/rv32_asm.py` (edit) | Shashwat | The assembler and golden simulator now also record every memory access in order (a **trace**). |
| `sw/cache_model.py` | Shashwat | A Python copy of the cache rules. Replays the trace and predicts the exact number of hits and misses. |
| `sw/programs/matmul.s`, `memcpy.s`, `unrolled_sum.s` | Shashwat | New test programs that stress the data cache, the write buffer and the instruction cache. |
| `tb/tb_hier.v` | Satyam | Testbench: runs a program to HALT, checks memory against the expected answer, prints the counters. |
| `tb/tb_l1_cache.v` | Satyam | 11 small direct tests for the cache (hit, miss, eviction, write buffer, RAW safety…). |
| `sim/run_hier.py` | Satyam | Runs all 266 combinations (programs × designs × latencies × sizes) in parallel and writes `docs/results_hier.csv`. |
| `synth/run_synth.sh` | Aaryan | Synthesis with Yosys, results in `docs/synth.csv`. |
| `docs/make_figures_phase2.py` | Satyam | Draws all Phase II charts. |

---

## 5. How we know it is correct

Every one of the 266 runs passes **three independent checks**:

1. **Correct answer:** the final data memory equals the answer computed by our Python
   simulator, word for word.
2. **Exact miss counts:** every hit and miss counter in the hardware equals the Python cache
   model's prediction **exactly**. This works because our caches are direct-mapped and never
   allocate on a store, so hits and misses depend only on the order of accesses, not on
   timing.
3. **Every cycle is explained:** `cycles = instructions + sum of all stall cycles`. Every cycle
   either finishes an instruction or has exactly one reason for stalling.

We also have unit tests: 9 address-decoder checks and 11 cache checks. Everything runs with
one command:

```bash
bash sim/run_all.sh
```

---

## 6. How to run things

```bash
bash sim/run_all.sh
```

```bash
python3 sim/run_hier.py
```

```bash
python3 docs/make_figures_phase2.py
```

```bash
bash synth/run_synth.sh
```

To present, open `docs/presentation.html` in Chrome or Safari:
- **→ / Space**: next step or slide. **←**: back.
- **N**: show speaker notes. **F**: full screen.
- Some slides reveal content step by step, so keep pressing → until the slide is complete.

Tools needed: Icarus Verilog (`iverilog`), Python 3 with matplotlib, and Yosys for synthesis.

---

## 7. Glossary

| Word | Meaning |
|---|---|
| **Harvard** | Separate memories (and paths) for instructions and data. |
| **Von Neumann** | One memory for both instructions and data. |
| **Modified Harvard** | Separate *caches* for instructions and data, one shared main memory below. |
| **Structural hazard** | Two things need the same hardware in the same cycle, so one waits. |
| **Stall** | A cycle where the CPU waits and does no useful work. |
| **CPI** | Cycles per instruction. Lower is better; 1.00 is ideal here. |
| **f_mem** | Fraction of instructions that are loads or stores. |
| **Latency (LAT)** | Cycles memory needs before the first word arrives. |
| **Cache** | Small fast memory holding copies of recently used lines. |
| **Line** | The block a cache moves at once (4 words = 16 bytes here). |
| **Hit / miss** | Found in the cache / not found, must go to main memory. |
| **Miss rate** | Misses ÷ accesses. |
| **Miss penalty** | Extra cycles a miss costs: LAT + words per line. |
| **AMAT** | Average memory access time = 1 + miss rate × miss penalty. |
| **Direct-mapped** | Each address has exactly one possible place in the cache. |
| **Tag / index / offset** | Parts of an address: which line, which set, which word. |
| **Conflict miss** | A miss because two addresses keep fighting for the same set. |
| **Write-through** | Every store also goes to main memory. |
| **Write buffer** | Holds a store so the CPU doesn't wait for slow memory. |
| **Arbiter** | Decides who uses a shared resource when two want it. |
| **Burst** | Several words sent one after another from a single request. |
| **ISS / golden model** | Our Python simulator that computes the correct answer. |
| **Synthesis** | Turning Verilog into real logic gates (LUTs, flip-flops). |
| **LUT** | Look-up table: the basic logic block in an FPGA. |

---

## 8. Five questions you will almost certainly be asked

1. **Why is Harvard faster?** Two independent memories, so a fetch and a load/store happen in
   the same cycle. Von Neumann needs one extra cycle per load/store.
2. **Then why don't all computers use pure Harvard?** Programs couldn't be treated as data (for
   example, loading a program from disk), and you need two memories. So real CPUs use
   **Modified Harvard**: split caches over one memory, which is our proposed design.
3. **Why did splitting without caches gain only 2 %?** Both paths end at the same slow
   single-port memory, so they still take turns.
4. **Why does the unified cache miss more with the same size?** Code and data map to the same
   sets (0x0000 and 0x1000), so they evict each other. It also has one port, so every
   load/store costs an extra cycle.
5. **How do you know the hardware is right?** Three checks on every run: correct final memory,
   exact miss counts vs the Python model, and every cycle accounted for. 266/266 pass.

For deeper questions and each member's file-by-file notes, see
[`INTERVIEW_PREP.md`](INTERVIEW_PREP.md).
