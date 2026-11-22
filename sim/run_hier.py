#!/usr/bin/env python3
"""
run_hier.py - Phase II regression + design-space sweep for the memory hierarchy.

For every (program, configuration) it
  1. compiles tb/tb_hier.v with Icarus Verilog for the requested top level,
  2. runs it (self-check of final memory against the ISS golden image),
  3. checks every cache counter against the golden cache model
     (sw/cache_model.py) - they must match EXACTLY,
  4. checks the cycle-accounting identity
        cycles = instret + st_imiss + st_dmiss + st_wbuf + st_io + st_struct
  5. appends one row to docs/results_hier.csv.

Configurations (the four organisations compared in the report):
  vn_flat     unified port, NO cache          (Von Neumann + slow memory)
  split_flat  split ports,  NO cache          (Harvard ports, shared slow memory)
  unified     unified L1 cache, 2*S lines     (Von Neumann hierarchy)
  split       L1 I$ + L1 D$, S lines each     (modified Harvard - PROPOSED)

Sweeps:  latency (S=16, line=4), L1 size (LAT=8, line=4), line size (LAT=8,
         256 B per split cache / 512 B unified).

Usage:  python3 sim/run_hier.py [--quick] [-j N]
"""
import argparse
import csv
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "sw"))
import rv32_asm      # noqa: E402
import cache_model   # noqa: E402

BUILD = os.path.join(ROOT, "sw", "build")
OUT = os.path.join(ROOT, "sim", "out", "hier")
RTL = [os.path.join(ROOT, "rtl", f + ".v") for f in (
    "pc", "addr_decoder", "rw_control", "io_regs", "regfile", "alu", "imm_gen",
    "control_unit", "cpu_core", "main_mem", "mem_arbiter", "l1_cache", "hier_perf",
    "modharvard_top", "unicache_top")]
STALLS = ("st_imiss", "st_dmiss", "st_wbuf", "st_io", "st_struct")
MODEL_KEYS = ("i_reads", "i_misses", "d_reads", "d_misses", "d_writes", "d_write_hits")

# arch name -> (define, tb arch, nocache, sets multiplier)
ARCHS = {
    "vn_flat":    ("UNICACHE",   "unified", 1, 2),
    "split_flat": ("MODHARVARD", "split",   1, 1),
    "unified":    ("UNICACHE",   "unified", 0, 2),
    "split":      ("MODHARVARD", "split",   0, 1),
}


def configs(quick):
    cfgs = set()
    lats = [8] if quick else [1, 2, 4, 8, 16]
    for lat in lats:                                    # latency sweep
        for a in ARCHS:
            cfgs.add((a, lat, 16, 4))
    if not quick:
        for s in (2, 4, 8, 16, 32, 64):                 # L1 size sweep
            for a in ("unified", "split"):
                cfgs.add((a, 8, s, 4))
        for line in (1, 2, 4, 8, 16):                   # line-size sweep
            for a in ("unified", "split"):
                cfgs.add((a, 8, 64 // line, line))
    return sorted(cfgs)


def run_one(prog, arch, lat, sets, line, model, vcd=""):
    define, tb_arch, nocache, mult = ARCHS[arch]
    hw_sets = 1 if nocache else sets * mult
    hw_line = 1 if nocache else line
    tag = f"{prog}_{arch}_L{lat}_S{sets}_W{line}"
    vvp = os.path.join(OUT, tag + ".vvp")
    P = lambda k, v: f"-Ptb_hier.{k}={v}"
    q = lambda s: f'"{s}"'
    cmd = ["iverilog", "-g2012", f"-D{define}", "-I", os.path.join(ROOT, "rtl"), "-o", vvp,
           P("PROG", q(f"{BUILD}/{prog}.hex")), P("DATA", q(f"{BUILD}/{prog}_data.hex")),
           P("EXPECT", q(f"{BUILD}/{prog}_expect.hex")), P("NAME", q(prog)),
           P("CFG", q(arch)), P("VCD", q(vcd)), P("LAT", lat), P("SETS", hw_sets),
           P("LINE", hw_line), P("NOCACHE", nocache),
           os.path.join(ROOT, "tb", "tb_hier.v")] + RTL
    subprocess.run(cmd, check=True, capture_output=True)
    log = subprocess.run(["vvp", "-n", vvp], check=True, capture_output=True, text=True).stdout
    os.remove(vvp)
    perf = next((l for l in log.splitlines() if l.startswith("PERF")), None)
    if perf is None:
        return {"program": prog, "arch": arch, "lat": lat, "sets": sets, "line": line,
                "self_check": "FAIL", "model_match": "NO", "accounting": "NO", "log": log}
    kv = {k: v for k, v in re.findall(r"(\w+)=(\S+)", perf)}
    r = {"program": prog, "arch": arch, "lat": lat, "sets": sets, "line": line,
         "l1_bytes": 0 if nocache else 2 * sets * line * 4}
    for k in ("cycles", "instret") + MODEL_KEYS + STALLS + ("conflict", "membusy", "parallel"):
        r[k] = int(kv[k])
    exp = cache_model.run(model["trace"], tb_arch, hw_sets, hw_line, bool(nocache))
    r["model_match"] = "yes" if all(r[k] == exp[k] for k in MODEL_KEYS) \
        and r["instret"] == model["instret"] else "NO"
    r["accounting"] = "yes" if r["cycles"] == r["instret"] + sum(r[s] for s in STALLS) else "NO"
    r["self_check"] = "PASS" if kv["errors"] == "0" else "FAIL"
    r["cpi"] = round(r["cycles"] / r["instret"], 3)
    reads = r["i_reads"] + r["d_reads"]
    r["i_miss_rate"] = round(r["i_misses"] / r["i_reads"], 4)
    r["d_miss_rate"] = round(r["d_misses"] / r["d_reads"], 4) if r["d_reads"] else 0.0
    r["miss_rate"] = round((r["i_misses"] + r["d_misses"]) / reads, 4)
    # AMAT for reads, in cycles: 1 (hit) + miss rate x miss penalty, penalty = LAT + line words
    r["amat"] = round(1 + r["miss_rate"] * (lat + hw_line), 3)
    if r["model_match"] != "yes" or r["accounting"] != "yes" or r["self_check"] != "PASS":
        r["log"] = log
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="only LAT=8 default configs")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)

    progs = sorted(os.path.splitext(f)[0] for f in os.listdir(os.path.join(ROOT, "sw", "programs"))
                   if f.endswith(".s"))
    models = {}
    for p in progs:
        src = os.path.join(ROOT, "sw", "programs", p + ".s")
        subprocess.run([sys.executable, os.path.join(ROOT, "sw", "rv32_asm.py"), src, BUILD],
                       check=True, capture_output=True)
        code, data, _, _ = rv32_asm.assemble(src)
        tr = []
        _, st = rv32_asm.simulate(code, data, trace=tr)
        models[p] = {"trace": tr, "instret": st["instret"]}

    jobs = [(p, *c) for p in progs for c in configs(args.quick)]
    with ThreadPoolExecutor(max_workers=args.j) as ex:
        rows = list(ex.map(lambda j: run_one(j[0], *j[1:], models[j[0]]), jobs))

    # waveform runs (default geometry, LAT=4) for the report figures
    for arch in ("split", "unified"):
        run_one("vector_add", arch, 4, 16, 4, models["vector_add"],
                vcd=os.path.join(OUT, f"vector_add_{arch}_L4.vcd"))

    bad = [r for r in rows if r["self_check"] != "PASS" or r["model_match"] != "yes"
           or r["accounting"] != "yes"]
    for r in bad:
        print(f"FAIL {r['program']} {r['arch']} L={r['lat']} S={r['sets']} W={r['line']}: "
              f"self={r['self_check']} model={r['model_match']} acct={r.get('accounting')}")
        print(r.get("log", "")[-800:])

    fields = ["program", "arch", "lat", "sets", "line", "l1_bytes", "cycles", "instret", "cpi",
              *MODEL_KEYS, "i_miss_rate", "d_miss_rate", "miss_rate", "amat", *STALLS,
              "conflict", "membusy", "parallel", "model_match", "accounting", "self_check"]
    with open(os.path.join(ROOT, "docs", "results_hier.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(sorted(rows, key=lambda r: (r["program"], r["arch"], r["lat"], r["sets"], r["line"])))

    # headline table: LAT=8, default geometry
    print("\nLAT=8, L1 = 256 B I$ + 256 B D$ (split) / 512 B unified, 16-byte lines")
    print("%-13s %7s | %9s %9s %9s %9s | %s" % ("program", "instr", "vn_flat", "split_flat",
                                               "unified", "split", "split speed-up vs vn_flat / unified"))
    for p in progs:
        c = {r["arch"]: r for r in rows if r["program"] == p and r["lat"] == 8
             and r["sets"] == 16 and r["line"] == 4}
        print("%-13s %7d | %9.2f %9.2f %9.2f %9.2f | %5.2fx / %4.2fx" % (
            p, c["split"]["instret"], c["vn_flat"]["cpi"], c["split_flat"]["cpi"],
            c["unified"]["cpi"], c["split"]["cpi"],
            c["vn_flat"]["cycles"] / c["split"]["cycles"],
            c["unified"]["cycles"] / c["split"]["cycles"]))
    print(f"\n{len(rows)} runs: {len(rows) - len(bad)} passed "
          f"(self-check + exact cache-model match + cycle accounting)")
    print("ALL HIERARCHY TESTS PASSED" if not bad else "SOME HIERARCHY TESTS FAILED")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
