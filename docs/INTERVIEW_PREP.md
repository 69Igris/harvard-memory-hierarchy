# Phase II interview preparation

Every member must be able to (1) explain the whole project in two minutes, (2) defend the
numbers, and (3) explain their own files line by line. Section A is for everyone; section B is
per member.

---

## A. Everyone

### The project in two minutes
1. A CPU makes two kinds of memory access: **fetch** an instruction every cycle, and **load/store**
   data for about 20–30 % of instructions.
2. **Von Neumann**: one memory and one port, so a load/store and the next fetch collide (a structural
   hazard). **Harvard**: separate instruction and data memories, so both happen in the same cycle.
3. **Phase I**: one single-cycle RV32I-subset core, used unchanged in both designs. Harvard runs at
   CPI = 1. Von Neumann runs at CPI = 1 + f_mem (f_mem = fraction of loads/stores), so it is up to
   1.31× slower. The hardware counters match the formula exactly.
4. **Phase II**: real memory is slow and shared. We added the brief's *optional shared lower-level
   memory*: an 8 KB main memory with latency LAT that holds code and data. We compare four
   organisations with the same core and the same memory: VN-flat, split-flat, unified L1, and
   split L1 (modified Harvard, proposed).
5. **Result at LAT = 8**: geo-mean CPI is 12.3 (VN-flat), 12.0 (split-flat), 2.81 (unified L1),
   and **2.01 (split L1)**. That is 1.40× faster than a unified cache of the same size and 6.1×
   faster than no cache, using about 5 % fewer LUTs.
6. **Key insight**: splitting the *paths* only helps when there is something private on each path.
   Without caches, the shared slow memory is the bottleneck (split ports gain only 2–8 %). With
   split L1 caches, hits proceed in parallel and the shared memory sees traffic only on misses.

### Numbers to remember
| Fact | Value |
|---|---|
| Phase I speed-up (Harvard vs VN) | 1.02× (fibonacci) … 1.31× (bubble_sort, vector_add) = 1 + f_mem |
| Phase II CPI at LAT=8 (VN-flat / split-flat / unified / split) | 12.28 / 12.01 / 2.81 / 2.01 |
| Split L1 vs unified L1 | 1.02× … 1.87×, geo-mean 1.40× |
| Read miss rate split vs unified | 4.0 % vs 8.9 % (geo-mean) |
| AMAT = 1 + miss_rate × (LAT + line words) | 1.64 vs 2.15 cycles |
| Miss penalty | LAT + words per line (8 cycles at LAT=4 with 4-word lines) |
| Back-to-back store penalty | LAT + 1 (write buffer has one entry) |
| Verification | 8 Phase I runs + 266 hierarchy runs + 9 decoder + 11 cache checks, all pass |
| Synthesis split vs unified | 1676 vs 1770 LUT, 303 vs 315 FF |

### Questions anyone may be asked
- **Why is Harvard faster?** Two independent ports, so fetch and load/store happen in the same cycle.
  Von Neumann needs one extra cycle for each load/store.
- **Why not always use Harvard?** Programs could not be treated as data (loading or patching code),
  and you need two memories. Real CPUs use *modified Harvard*: split L1 caches over one unified
  memory, so software sees one address space.
- **What is a modified Harvard architecture?** Split instruction/data caches (Harvard at L1) over a
  shared lower level (Von Neumann below). That is exactly `modharvard_top.v`.
- **Why did split ports without caches gain so little?** Both paths end at the same single-ported
  slow memory. The instruction fetch must finish before the data access can start, so they still
  take turns.
- **Why does the unified cache miss more with the same capacity?** Code starts at 0x0000 and data
  at 0x1000. 4 KB is a multiple of the cache size, so the first code lines and the first data lines
  map to the same sets of a direct-mapped cache and keep evicting each other (conflict misses).
  matmul has a 55 % D-miss rate unified vs 6 % split.
- **When is unified better?** When one stream needs more than half the capacity. unrolled_sum has a
  512 B loop body: its I-miss rate is 16 % unified vs 25 % with a 256 B I-cache. Split still wins
  overall (1.11×) because unified pays a port-conflict cycle on every load/store.
- **How do you know the hardware is correct?** Three independent checks per run: final memory equals
  the Python ISS image; every cache counter equals the Python cache model *exactly*; and
  cycles = instret + Σ stalls. Plus directed unit tests.
- **Why can the cache model predict hardware miss counts exactly?** The caches are direct-mapped and
  never allocate on a write, so hits and misses depend only on the access order, not on timing.
- **What is the "simultaneous access" result?** The split design's *parallel* counter (cycles with
  an I-hit and a D-access together) equals the unified design's port-conflict stalls, minus the one
  uncached HALT store: 48 vs 49 for vector_add, 144 vs 145 for matmul. The arbiter sees both caches
  requesting at most once per program.
- **Limitations?** Single-cycle core, direct-mapped caches, one-entry write buffer, no
  place-and-route Fmax. Next steps: a pipeline, set-associative caches, a deeper write buffer, FPGA.

---

## B. Per member (know these files line by line)

### Aaryan Yadav: core and Phase II integration
Files: `pc.v`, `regfile.v`, `alu.v`, `imm_gen.v`, `control_unit.v`, `cpu_core.v`,
`modharvard_top.v`, `synth/`.
- Single-cycle datapath: PC → instruction → decode → regfile → ALU → data port → write-back mux.
- `stall` freezes the PC, regfile writes and store strobes, and that is all a memory system needs
  from the core.
- **Why `d_wreq` was added**: `d_write` is gated by `~stall`. If the cache used it to *decide* to
  stall, there would be a combinational loop (stall → d_write → stall). `d_wreq` is the ungated
  request.
- In `modharvard_top`: `core_stall = halted | i_stall | d_stall | io_wait`. Data requests are
  masked with `~i_stall`, because during an I-miss the "instruction" is a NOP placeholder.
- Synthesis: `synth_xilinx`. The counters have no output pins, so they are optimised away. The
  "path" metric is relative only; there is no P&R and no Fmax.

### Shashwat Sinha: instruction side, software, golden models
Files: `imem.v`, `sw/rv32_asm.py`, `sw/cache_model.py`, `sw/programs/*.s`.
- Two-pass assembler: pass 1 assigns label addresses, pass 2 encodes. `li`/`la` always expand to
  two words so pass-1 sizes stay fixed.
- The ISS produces the expected final memory and, in Phase II, a trace of (I/R/W, address) in
  program order.
- `cache_model.py` replays the trace through direct-mapped, write-through, no-allocate caches.
  Split: fetches go to the I-cache and loads/stores to the D-cache. Unified: the fetch, then the
  data access, both go to one cache.
- New programs: `matmul` (function calls and a shift-add multiply, 2596 instructions), `memcpy`
  (streaming, back-to-back stores, stresses the write buffer), `unrolled_sum` (512 B code body,
  stresses the I-cache).

### Shivam Mishra: data side and the L1 cache
Files: `dmem.v`, `addr_decoder.v`, `rw_control.v`, `io_regs.v`, `harvard_top.v`, `l1_cache.v`.
- Decoder: upper address bits → one-hot select (data memory / I/O / bus error). In Harvard mode a
  data access to the code region is a bus error.
- `l1_cache.v`: index = (word / LINE) % SETS, tag = word / (LINE × SETS). Hits are combinational.
  A miss refills the whole line as a burst; penalty = LAT + LINE.
- Write-through, no-write-allocate, 1-entry write buffer. A store finishes in 1 cycle and drains in
  the background. **A read miss waits for the buffer to drain**, so the refill reads the updated
  memory (RAW safety, unit-test check 6).
- One write port per array and no reset, so the arrays map to LUT-RAM. The first version had two
  write ports and needed 2 k flip-flops per cache. Refill and store-hit writes can never happen in
  the same cycle.
- I/O is uncached and waits for the write buffer (a fence), so HALT always happens after the last
  store reaches memory.

### Himank Kaushik: shared memory, arbiter, baselines, counters
Files: `unified_mem.v`, `vonneumann_top.v`, `perf_counters.v`, `main_mem.v`, `mem_arbiter.v`,
`unicache_top.v`, `hier_perf.v`.
- `main_mem`: accepted at cycle t, first word at t + LAT, then one word per cycle. Writes take LAT.
- `mem_arbiter`: grants only when memory is idle. The I-side has priority because an I-miss always
  stalls the core and a store drain usually doesn't. The owner is latched to route the burst back.
  `conflict` = both caches requesting.
- `unicache_top`: the Phase I FETCH/DATA arbiter, now in front of a unified cache. A fetched
  load/store is latched into IR, so it costs one structural cycle.
- `hier_perf`: every cycle is a retire or exactly one stall cause (I-miss, D-miss, write buffer,
  I/O, port conflict), which is why the accounting identity holds.
- AMAT = hit time + miss rate × miss penalty = 1 + m × (LAT + LINE).

### Satyam Kumar: verification, analysis, documentation
Files: `tb_top.v`, `tb_addr_decoder.v`, `tb_hier.v`, `tb_l1_cache.v`, `sim/*`,
`docs/make_figures*.py`, `report/`.
- `tb_hier.v`: run to HALT, check the write buffer is empty, compare 1024 data words in main memory
  with the golden image, print the PERF line.
- `run_hier.py`: compiles each (program, configuration), runs it, checks the model match and cycle
  accounting, writes `docs/results_hier.csv`. 266 runs in a few seconds (parallel).
- Sweeps: latency 1–16; L1 size 64 B–2 KB; line size 4–64 B at a fixed 512 B. Unified gets worse
  at 64 B lines: only 8 lines, so code and data thrash.
- Reading the waveform (`wave_hierarchy.png`): a lw miss holds the core for 8 cycles (LAT 4 + 4
  words). Afterwards each sw completes in 1 cycle while "D write" drains to memory and the next
  instructions keep hitting.
