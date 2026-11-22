#!/usr/bin/env python3
"""make_figures_phase2.py - figures for the Phase II memory-hierarchy study.

    python3 sim/run_hier.py && python3 docs/make_figures_phase2.py

Outputs (docs/figures/):
    block_hierarchy.png      modified-Harvard hierarchy vs unified-cache baseline
    cpi_vs_latency.png       mean CPI of the 4 organisations vs main-memory latency
    stall_breakdown.png      where the cycles go (LAT=8), unified vs split
    l1_size_sweep.png        miss rate + CPI vs L1 capacity
    line_size_sweep.png      miss rate + CPI vs line size (fixed capacity)
    wave_hierarchy.png       split-L1 waveform: refills, write-buffer drain, overlap
"""
import csv
import math
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
from vcdvcd import VCDVCD

from make_figures import box, arrow, BLUE, ORANGE, INK, INK2, MUTED, GRID, FIG, ROOT

TEAL, PURPLE = "#1f9e89", "#8a5cc2"
plt.rcParams["text.parse_math"] = False          # labels contain "I$" / "D$"
ARCH = {   # key: (label, colour, marker)
    "split":      ("Split L1 I$ + D$ (modified Harvard)", BLUE, "o"),
    "unified":    ("Unified L1 cache (Von Neumann)", ORANGE, "s"),
    "split_flat": ("Split ports, no cache", TEAL, "^"),
    "vn_flat":    ("Unified port, no cache", PURPLE, "D"),
}
OUT = os.path.join(ROOT, "sim", "out", "hier")
rows = list(csv.DictReader(open(os.path.join(ROOT, "docs", "results_hier.csv"))))
for r in rows:
    for k, v in r.items():
        try:
            r[k] = int(v)
        except ValueError:
            try:
                r[k] = float(v)
            except ValueError:
                pass
PROGS = sorted({r["program"] for r in rows})


def gmean(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs))


def pick(arch, lat, sets, line):
    return [r for r in rows if r["arch"] == arch and r["lat"] == lat and r["sets"] == sets
            and r["line"] == line]


def style(ax, title, ylabel, xlabel):
    ax.spines[["top", "right"]].set_visible(False)
    ax.yaxis.grid(True, color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    ax.set_title(title, loc="left", fontsize=11, color=INK)
    ax.set_ylabel(ylabel)
    ax.set_xlabel(xlabel)


def save(fig, name):
    fig.savefig(os.path.join(FIG, name), dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)


# --------------------------------------------------------------- block diagram
def block_hierarchy():
    fig, ax = plt.subplots(figsize=(10, 6.2))
    ax.set_xlim(0, 12.6); ax.set_ylim(0, 7.8); ax.axis("off")
    # ---- (a) proposed
    ax.text(0.2, 7.5, "(a) Proposed: modified Harvard hierarchy (modharvard_top.v)",
            fontsize=10, fontweight="bold", color=BLUE)
    box(ax, 0.3, 4.5, 2.2, 2.4, "cpu_core", "RV32I, single-cycle", fc="#f4f7fc", ec=BLUE)
    box(ax, 3.4, 5.9, 2.6, 1.0, "L1 I-cache", "256 B, read-only", fc="#eef4fc", ec=BLUE)
    box(ax, 3.4, 4.5, 2.6, 1.0, "Decoder + R/W ctrl", "address map")
    box(ax, 6.8, 4.5, 2.2, 1.0, "L1 D-cache", "256 B, WT + buffer", fc="#eef4fc", ec=BLUE)
    box(ax, 6.8, 3.2, 2.2, 0.9, "MMIO", "uncached")
    box(ax, 9.6, 5.25, 1.3, 1.0, "Arbiter", "I first")
    box(ax, 11.2, 4.95, 1.3, 1.6, "Main", "memory")
    ax.text(11.85, 4.75, "8 KB, LAT", ha="center", fontsize=8, color=INK2)
    arrow(ax, 2.5, 6.4, 3.4, 6.4, "I-port", BLUE, both=True)
    arrow(ax, 2.5, 5.0, 3.4, 5.0, "D-port", INK2, both=True)
    arrow(ax, 6.0, 5.0, 6.8, 5.0, "", INK2, both=True)
    ax.plot([4.7, 4.7], [4.5, 3.65], color=INK2, lw=1.6)
    arrow(ax, 4.7, 3.65, 6.8, 3.65, "0x20xx", INK2, off=(0, 0.04))
    arrow(ax, 6.0, 6.4, 9.6, 6.0, "I miss: line refill", BLUE, both=True, off=(0, 0.08))
    arrow(ax, 9.0, 5.0, 9.6, 5.5, "", INK2, both=True)
    ax.text(9.05, 4.65, "D miss /\nstore drain", fontsize=8, color=INK2, va="top")
    arrow(ax, 10.9, 5.75, 11.2, 5.75, "", INK, both=True, lw=2.2)
    ax.text(0.3, 2.75, "Hits in both L1s happen in the SAME cycle; instruction and data traffic meet "
            "only at the shared level, on misses and write-buffer drains.", fontsize=8.5, color=INK)
    # ---- (b) baseline
    ax.text(0.2, 2.25, "(b) Baseline: Von Neumann hierarchy (unicache_top.v)",
            fontsize=10, fontweight="bold", color=ORANGE)
    box(ax, 0.3, 0.2, 2.2, 1.7, "cpu_core", "same RTL", fc="#fdf3ee", ec=ORANGE)
    box(ax, 3.4, 0.4, 2.6, 1.3, "FETCH/DATA", "port arbiter + IR", fc="#fff8f4", ec=ORANGE)
    box(ax, 6.8, 0.4, 2.4, 1.3, "Unified L1", "512 B, one port", fc="#fdf3ee", ec=ORANGE)
    box(ax, 10.2, 0.4, 2.3, 1.3, "Main memory", "same 8 KB, LAT", fc="#f4f4f2")
    arrow(ax, 2.5, 1.4, 3.4, 1.4, "I-port", ORANGE, both=True)
    arrow(ax, 2.5, 0.7, 3.4, 0.7, "D-port", ORANGE, both=True)
    arrow(ax, 6.0, 1.05, 6.8, 1.05, "1 port", ORANGE, both=True, lw=2.2)
    arrow(ax, 9.2, 1.05, 10.2, 1.05, "", INK, both=True, lw=2.2)
    ax.text(3.4, 0.05, "+1 cycle per load/store (structural hazard); code and data share cache lines",
            fontsize=8, color=INK2)
    save(fig, "block_hierarchy.png")


# --------------------------------------------------------------- latency sweep
def cpi_vs_latency():
    fig, ax = plt.subplots(figsize=(8, 4.4))
    lats = [1, 2, 4, 8, 16]
    for a in ("vn_flat", "split_flat", "unified", "split"):
        label, col, mk = ARCH[a]
        ys = [gmean([r["cpi"] for r in pick(a, L, 16, 4)]) for L in lats]
        ax.plot(lats, ys, color=col, lw=2, marker=mk, ms=8, mec="white", mew=1.5, label=label)
        if a in ("split", "unified"):
            ax.text(16.9, ys[-1], f"{ys[-1]:.2f}", va="center", fontsize=9, color=INK)
        elif a == "vn_flat":
            ax.text(16.9, ys[-1], f"~{ys[-1]:.0f}", va="center", fontsize=9, color=INK)
    ax.axhline(1.0, color=MUTED, lw=1, ls="--")
    ax.text(1.05, 1.08, "ideal Phase I Harvard, CPI = 1", fontsize=8, color=INK2)
    ax.set_xscale("log", base=2); ax.set_yscale("log", base=2)
    ax.set_xticks(lats); ax.set_xticklabels(lats)
    ax.set_yticks([1, 2, 4, 8, 16]); ax.set_yticklabels(["1", "2", "4", "8", "16"])
    ax.set_xlim(0.9, 20)
    style(ax, "Mean CPI (geo-mean of 7 programs) vs main-memory latency",
          "CPI (log scale)", "main-memory first-word latency LAT (cycles, log scale)")
    ax.legend(frameon=False, fontsize=8.5, loc="upper left")
    save(fig, "cpi_vs_latency.png")


# --------------------------------------------------------------- stall breakdown
def stall_breakdown():
    cats = [("instret", "useful (retire)", "#c9c8c3"), ("st_imiss", "I-miss stall", BLUE),
            ("st_dmiss", "D-miss stall", TEAL), ("st_wbuf", "write-buffer stall", PURPLE),
            ("st_struct", "port conflict (ld/st)", ORANGE)]
    fig, ax = plt.subplots(figsize=(10, 4.6))
    w = 0.38
    for i, p in enumerate(PROGS):
        for j, a in enumerate(("unified", "split")):
            r = pick(a, 8, 16, 4)
            r = next(x for x in r if x["program"] == p)
            x = i + (j - 0.5) * (w + 0.04)
            bottom = 0
            for k, _, col in cats:
                v = r[k] / r["instret"]
                ax.bar(x, v, w, bottom=bottom, color=col, edgecolor="white", linewidth=1)
                bottom += v
            ax.text(x, bottom + 0.05, "U" if a == "unified" else "S", ha="center",
                    fontsize=8, color=INK2)
    for _, lab, col in cats:
        ax.bar(0, 0, color=col, label=lab)
    ax.set_xticks(range(len(PROGS))); ax.set_xticklabels(PROGS, fontsize=9)
    style(ax, "Cycles per instruction, broken down by cause (LAT = 8; U = unified 512 B, S = split 2x256 B)",
          "cycles / instruction", "")
    ax.legend(frameon=False, fontsize=8.5, ncol=5, loc="upper center", bbox_to_anchor=(0.5, -0.1))
    save(fig, "stall_breakdown.png")


# --------------------------------------------------------------- size / line sweeps
def sweep(kind):
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(10, 4))
    if kind == "size":
        xs = [2, 4, 8, 16, 32, 64]
        key = lambda s: (8, s, 4)
        xl = [f"{2 * s * 16}" for s in xs]
        xlabel = "total L1 capacity (bytes)"
    else:
        xs = [1, 2, 4, 8, 16]
        key = lambda l: (8, 64 // l, l)
        xl = [str(4 * l) for l in xs]
        xlabel = "line size (bytes), capacity fixed at 512 B total"
    for a in ("unified", "split"):
        label, col, mk = ARCH[a]
        mr = [gmean([max(r["miss_rate"], 1e-4) for r in pick(a, *key(x))]) * 100 for x in xs]
        cpi = [gmean([r["cpi"] for r in pick(a, *key(x))]) for x in xs]
        a1.plot(range(len(xs)), mr, color=col, lw=2, marker=mk, ms=8, mec="white", mew=1.5, label=label)
        a2.plot(range(len(xs)), cpi, color=col, lw=2, marker=mk, ms=8, mec="white", mew=1.5, label=label)
        a2.text(len(xs) - 0.85, cpi[-1], f"{cpi[-1]:.2f}", va="center", fontsize=9, color=INK)
    for ax, t, y in ((a1, "Read miss rate (geo-mean)", "miss rate (%)"),
                     (a2, "CPI (geo-mean), LAT = 8", "CPI")):
        ax.set_xticks(range(len(xs))); ax.set_xticklabels(xl)
        style(ax, t, y, xlabel)
    a1.legend(frameon=False, fontsize=8.5)
    save(fig, "l1_size_sweep.png" if kind == "size" else "line_size_sweep.png")


# --------------------------------------------------------------- waveform
def wave_hierarchy(start=118, n=40, name="vector_add"):
    vcd = VCDVCD(os.path.join(OUT, f"{name}_split_L4.vcd"), store_tvs=True)
    lst = {}
    for line in open(os.path.join(ROOT, "sw", "build", f"{name}.lst")):
        pc, _, txt = line.rstrip("\n").split("  ", 2)
        lst[int(pc, 16)] = txt
    p = "tb_hier.dut."
    names = vcd.signals

    def get(sig, t):
        for nm in names:
            if nm == sig or nm.split("[")[0] == sig:
                v = vcd[nm][t]
                return int(v.replace("x", "0").replace("z", "0"), 2)
        raise KeyError(sig)

    period, t0 = 10_000, 15_000
    times = [t0 + (start + k) * period + 6_000 for k in range(n)]
    D = defaultdict(list)
    for t in times:
        stall = get(p + "core_stall", t)
        i_ref = get(p + "i_refilling", t)
        istall = get(p + "i_stall", t)
        pc = get(p + "i_addr", t)
        D["PC"].append(pc)
        D["instruction"].append(None if istall else lst.get(pc, "?").split()[0])
        D["I$ hit"].append(0 if istall else 1)
        rd, wr = get(p + "d_rd", t), get(p + "d_wr", t)
        D["D$ access"].append(("lw" if rd else "sw") if (rd or wr) and not istall else None)
        D["D$ hit"].append(1 if (rd or wr) and not istall and get(p + "d_hit", t) else 0)
        D["core stall"].append(stall)
        busy = get(p + "m_busy", t)
        owner = get(p + "u_arb.owner_i", t)
        if not busy:
            D["shared memory"].append(None)
        elif owner:
            D["shared memory"].append("I refill")
        elif get(p + "d_draining", t):
            D["shared memory"].append("D write")
        else:
            D["shared memory"].append("D refill")
    rows_ = [("clk", None), ("PC", "bus"), ("instruction", "bus"), ("I$ hit", "bit"),
             ("D$ access", "bus"), ("D$ hit", "bit"), ("shared memory", "bus"), ("core stall", "bit")]
    nr = len(rows_)
    fig, ax = plt.subplots(figsize=(13, 0.55 * nr + 1))
    ax.set_xlim(-3.2, n); ax.set_ylim(-0.6, nr - 0.2); ax.axis("off")
    for c in range(n + 1):
        ax.axvline(c, color=GRID, lw=0.6, zorder=0)
    fills = {"I refill": "#dbe8f8", "D refill": "#d6efe9", "D write": "#e8def4"}
    for i, (label, kind) in enumerate(rows_):
        y = nr - 1 - i
        ax.text(-0.25, y + 0.33, label, ha="right", va="center", fontsize=9, color=INK)
        if label == "clk":
            xs, ys = [], []
            for c in range(n):
                xs += [c, c + 0.5, c + 0.5, c + 1]; ys += [y + 0.6, y + 0.6, y, y]
            ax.plot(xs, ys, color=INK2, lw=1)
            continue
        vals = D[label]
        if kind == "bit":
            col = ORANGE if label == "core stall" else (TEAL if label == "D$ hit" else BLUE)
            xs, ys = [], []
            for c, v in enumerate(vals):
                xs += [c, c + 1]; ys += [y + 0.6 * v] * 2
                if v:
                    ax.fill_between([c, c + 1], y, y + 0.6, color=col, alpha=0.15, lw=0)
            ax.plot(xs, ys, color=col, lw=1.8)
            continue
        c = 0
        while c < n:
            v, e = vals[c], c
            while e + 1 < n and vals[e + 1] == v:
                e += 1
            if v is not None:
                x0, x1 = c + 0.06, e + 1 - 0.06
                ax.add_patch(FancyBboxPatch((x0, y + 0.05), x1 - x0, 0.55,
                             boxstyle="round,pad=0,rounding_size=0.12",
                             fc=fills.get(v, "#ffffff"), ec=INK2, lw=0.9))
                txt = f"{v:02x}" if isinstance(v, int) else str(v)
                ax.text((x0 + x1) / 2, y + 0.33, txt, ha="center", va="center",
                        fontsize=7 if label == "PC" else 7.5, color=INK, clip_on=True)
            c = e + 1
    for c in range(0, n, 2):
        ax.text(c + 0.5, -0.45, str(start + c), ha="center", fontsize=7, color=MUTED)
    ax.text(-0.25, -0.45, "cycle", ha="right", fontsize=7, color=MUTED)
    ax.set_title("Split L1 hierarchy, vector_add, LAT = 4: line refills stall the core; "
                 "the store drains in the background while I$/D$ hits continue",
                 loc="left", fontsize=10.5, color=INK, pad=6)
    save(fig, "wave_hierarchy.png")


if __name__ == "__main__":
    block_hierarchy()
    cpi_vs_latency()
    stall_breakdown()
    sweep("size")
    sweep("line")
    wave_hierarchy()
    print("phase II figures written to", FIG)
