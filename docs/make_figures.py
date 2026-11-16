#!/usr/bin/env python3
"""make_figures.py - regenerate every figure used in the report and video.

    python3 docs/make_figures.py        (run sim/run_all.sh first)

Outputs (docs/figures/):
    block_harvard.png, block_vonneumann.png   architecture block diagrams
    wave_harvard.png, wave_vonneumann.png     waveforms (same 24-cycle window)
    cycles_comparison.png                     cycle count per program
"""
import csv
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
from vcdvcd import VCDVCD

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIG = os.path.join(ROOT, "docs", "figures")
OUT = os.path.join(ROOT, "sim", "out")
os.makedirs(FIG, exist_ok=True)

BLUE, ORANGE = "#2a78d6", "#eb6834"          # Harvard, Von Neumann
INK, INK2, MUTED, GRID = "#0b0b0b", "#52514e", "#8a8984", "#e4e3df"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                     "axes.edgecolor": MUTED, "axes.labelcolor": INK2,
                     "xtick.color": INK2, "ytick.color": INK2})


# --------------------------------------------------------------- block diagrams
def box(ax, x, y, w, h, title, sub="", fc="#ffffff", ec=INK2, bold=True):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.12",
                                fc=fc, ec=ec, lw=1.4))
    ax.text(x + w / 2, y + h / 2 + (0.14 if sub else 0), title, ha="center", va="center",
            fontsize=9.5, fontweight="bold" if bold else "normal", color=INK)
    if sub:
        ax.text(x + w / 2, y + h / 2 - 0.2, sub, ha="center", va="center", fontsize=8, color=INK2)


def arrow(ax, x1, y1, x2, y2, label="", color=INK2, both=False, lw=1.6, off=(0, 0.13)):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="<|-|>" if both else "-|>", color=color, lw=lw,
                                shrinkA=0, shrinkB=0, mutation_scale=12))
    if label:
        ax.text((x1 + x2) / 2 + off[0], (y1 + y2) / 2 + off[1], label, ha="center",
                va="bottom", fontsize=8, color=color)


def block_harvard():
    fig, ax = plt.subplots(figsize=(9.2, 4.6))
    ax.set_xlim(0, 11.5); ax.set_ylim(0, 5.6); ax.axis("off")
    # core
    ax.add_patch(FancyBboxPatch((0.3, 0.5), 3.6, 4.6, boxstyle="round,pad=0.02,rounding_size=0.15",
                                fc="#f4f7fc", ec=BLUE, lw=1.6))
    ax.text(2.1, 4.8, "cpu_core (RV32I, single-cycle)", ha="center", fontsize=9, color=BLUE, fontweight="bold")
    box(ax, 0.6, 3.5, 1.4, 0.9, "PC", "pc.v")
    box(ax, 2.2, 3.5, 1.5, 0.9, "Control", "control_unit.v")
    box(ax, 0.6, 2.1, 1.4, 0.9, "RegFile", "32 x 32")
    box(ax, 2.2, 2.1, 1.5, 0.9, "ALU", "+ imm_gen")
    box(ax, 0.6, 0.8, 3.1, 0.9, "Write-back MUX", "ALU / MEM / PC+4")
    # instruction side
    box(ax, 5.6, 3.6, 2.2, 1.1, "Instruction Mem", "imem.v  4 KB ROM", fc="#eef4fc", ec=BLUE)
    arrow(ax, 3.9, 4.3, 5.6, 4.3, "I-addr (PC)", BLUE)
    arrow(ax, 5.6, 3.85, 3.9, 3.85, "instruction", BLUE)
    # data side
    box(ax, 5.6, 1.5, 2.2, 1.1, "Address Decoder", "addr_decoder.v")
    box(ax, 5.6, 0.2, 2.2, 0.9, "R/W Control", "rw_control.v")
    box(ax, 8.6, 2.2, 2.5, 1.0, "Data Memory", "dmem.v  4 KB RAM", fc="#eef4fc", ec=BLUE)
    box(ax, 8.6, 0.6, 2.5, 1.0, "MMIO (0x2000)", "OUT / HALT / CYCLE")
    arrow(ax, 3.9, 2.3, 5.6, 2.3, "D-addr / wdata", INK2)
    arrow(ax, 4.75, 2.3, 4.75, 0.65, "", INK2)
    arrow(ax, 4.75, 0.65, 5.6, 0.65, "rd / wr", INK2, off=(0, 0.05))
    arrow(ax, 7.8, 2.2, 8.6, 2.7, "", INK2)
    arrow(ax, 7.8, 1.8, 8.6, 1.2, "", INK2)
    ax.text(8.15, 2.6, "0x1xxx", fontsize=7.5, color=INK2, ha="center")
    ax.text(8.15, 1.35, "0x20xx", fontsize=7.5, color=INK2, ha="center")
    arrow(ax, 5.6, 0.35, 3.9, 0.35, "read data", INK2, off=(0, 0.03))
    ax.text(5.75, 5.25, "Two independent buses: fetch and load/store in the SAME cycle",
            ha="left", fontsize=9, color=INK)
    fig.savefig(os.path.join(FIG, "block_harvard.png"), dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def block_vonneumann():
    fig, ax = plt.subplots(figsize=(9.2, 4.0))
    ax.set_xlim(0, 11.5); ax.set_ylim(0, 4.8); ax.axis("off")
    ax.add_patch(FancyBboxPatch((0.3, 0.5), 3.2, 3.6, boxstyle="round,pad=0.02,rounding_size=0.15",
                                fc="#fdf3ee", ec=ORANGE, lw=1.6))
    ax.text(1.9, 3.8, "cpu_core (same RTL)", ha="center", fontsize=9, color=ORANGE, fontweight="bold")
    box(ax, 0.6, 2.4, 2.6, 0.9, "I-port", "PC -> instruction")
    box(ax, 0.6, 0.9, 2.6, 0.9, "D-port", "load / store")
    box(ax, 4.5, 1.2, 2.3, 2.0, "Arbiter FSM", "FETCH <-> DATA\nstall on ld/st", fc="#fff8f4", ec=ORANGE)
    box(ax, 8.0, 1.2, 3.0, 2.0, "Unified Memory", "unified_mem.v 8 KB\ncode + data, 1 port", fc="#fdf3ee", ec=ORANGE)
    arrow(ax, 3.5, 2.85, 4.5, 2.85, "", ORANGE, both=True)
    arrow(ax, 3.5, 1.35, 4.5, 1.35, "", ORANGE, both=True)
    arrow(ax, 6.8, 2.2, 8.0, 2.2, "ONE\nshared bus", ORANGE, both=True, lw=2.4, off=(0, -0.75))
    arrow(ax, 4.0, 1.35, 4.0, 0.3, "", INK2)
    ax.text(4.1, 0.25, "stall -> PC frozen 1 cycle per load/store", fontsize=8, color=INK2, va="center")
    ax.text(4.5, 4.35, "Baseline: instruction fetch and data access compete for one port",
            ha="left", fontsize=9, color=INK)
    fig.savefig(os.path.join(FIG, "block_vonneumann.png"), dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)


# --------------------------------------------------------------- waveforms
def load_listing(name):
    lst = {}
    for line in open(os.path.join(ROOT, "sw", "build", f"{name}.lst")):
        pc, _, txt = line.rstrip("\n").split("  ", 2)
        lst[int(pc, 16)] = txt
    return lst


def sample(vcd, sig, t):
    """value of signal 'sig' just before time t (string of bits, may contain x)."""
    return vcd[sig][t]


def waveform(arch, color, title, start_cycle=10, n_cycles=24, name="vector_add"):
    vcd = VCDVCD(os.path.join(OUT, f"{name}_{arch}.vcd"), store_tvs=True)
    period, t0 = 10_000, 15_000           # 10 ns clock (ps); cycle 0 starts at the 15 ns edge
    lst = load_listing(name)
    p = "tb_top.dut."
    rows = [("clk", "tb_top.clk", 1),
            ("PC (I-addr)", p + "i_addr", 32),
            ("instruction", None, 0),
            ("I-bus fetch", None, 1),
            ("D-addr", p + "u_core.d_addr", 32),
            ("D-read", None, 1),
            ("D-write", None, 1),
            ("stall", None, 1)]
    if arch == "vonneumann":
        rows.insert(4, ("bus owner", None, 0))

    times = [t0 + (start_cycle + k) * period + 6_000 for k in range(n_cycles)]  # mid-cycle samples
    names = vcd.signals
    def resolve(sig):
        for nm in names:
            if nm == sig or nm.split("[")[0] == sig:
                return nm
        raise KeyError(sig)
    def get(sig, t):
        try:
            return int(vcd[resolve(sig)][t].replace("x", "0").replace("z", "0"), 2)
        except Exception:
            return 0

    data = {r[0]: [] for r in rows}
    for t in times:
        pc = get(p + "i_addr", t)
        in_data = arch == "vonneumann" and get(p + "state", t) == 1
        stall = get(p + "arb_stall", t) if arch == "vonneumann" else 0
        rd, wr = get(p + "u_core.d_read", t), get(p + "u_core.mem_write", t)
        is_mem = rd or wr
        data["PC (I-addr)"].append(pc)
        data["instruction"].append(lst.get(pc, "?").split()[0])
        data["I-bus fetch"].append(0 if in_data else 1)
        data["D-addr"].append(get(p + "u_core.d_addr", t) if (is_mem and (arch == "harvard" or in_data)) else None)
        data["D-read"].append(1 if rd and (arch == "harvard" or in_data) else 0)
        data["D-write"].append(1 if wr and (arch == "harvard" or in_data) else 0)
        data["stall"].append(stall)
        if arch == "vonneumann":
            data["bus owner"].append("DATA" if in_data else "FETCH")

    n = len(rows)
    fig, ax = plt.subplots(figsize=(12, 0.52 * n + 0.9))
    ax.set_xlim(-3.6, n_cycles); ax.set_ylim(-0.6, n - 0.2); ax.axis("off")
    for c in range(n_cycles + 1):
        ax.axvline(c, color=GRID, lw=0.6, zorder=0)
    for i, (label, sig, width) in enumerate(rows):
        y = n - 1 - i
        ax.text(-0.25, y + 0.35, label, ha="right", va="center", fontsize=9, color=INK)
        if label == "clk":
            xs, ys = [], []
            for c in range(n_cycles):
                xs += [c, c + 0.5, c + 0.5, c + 1]; ys += [y + 0.7, y + 0.7, y, y]
            ax.plot(xs, ys, color=INK2, lw=1.1)
            continue
        vals = data[label]
        if label in ("I-bus fetch", "D-read", "D-write", "stall"):
            col = ORANGE if label == "stall" else color
            xs, ys = [], []
            for c, v in enumerate(vals):
                xs += [c, c + 1]; ys += [y + 0.6 * v, y + 0.6 * v]
            ax.plot(xs, ys, color=col, lw=1.8, drawstyle="steps-post")
            for c, v in enumerate(vals):
                if v:
                    ax.fill_between([c, c + 1], y, y + 0.6, color=col, alpha=0.15, lw=0)
            continue
        # bus-style row: merge equal consecutive values
        c = 0
        while c < n_cycles:
            v, e = vals[c], c
            while e + 1 < n_cycles and vals[e + 1] == v:
                e += 1
            if v is not None:
                x0, x1 = c + 0.06, e + 1 - 0.06
                fc = "#ffffff"
                if label == "bus owner":
                    fc = "#fde3d8" if v == "DATA" else "#f4f4f2"
                ax.add_patch(FancyBboxPatch((x0, y + 0.05), x1 - x0, 0.55,
                             boxstyle="round,pad=0,rounding_size=0.12", fc=fc, ec=color, lw=1.0))
                txt = f"{v:04x}" if isinstance(v, int) else str(v)
                if label == "instruction":
                    txt = txt.replace("  ", " ")
                fs = 8 if label == "instruction" else 7.5
                ax.text((x0 + x1) / 2, y + 0.33, txt, ha="center", va="center", fontsize=fs,
                        color=INK, clip_on=True)
            c = e + 1
    for c in range(0, n_cycles, 2):
        ax.text(c + 0.5, -0.45, str(start_cycle + c), ha="center", fontsize=7, color=MUTED)
    ax.text(-0.25, -0.45, "cycle", ha="right", fontsize=7, color=MUTED)
    ax.set_title(title, loc="left", fontsize=11, color=INK, pad=6)
    fig.savefig(os.path.join(FIG, f"wave_{arch}.png"), dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)


# --------------------------------------------------------------- cycle chart
def cycles_chart():
    rows = list(csv.DictReader(open(os.path.join(ROOT, "docs", "results.csv"))))
    order = sorted(rows, key=lambda r: float(r["mem_fraction"]))
    names = [f'{r["program"]}\n({100*float(r["mem_fraction"]):.0f}% ld/st)' for r in order]
    h = [int(r["harvard_cycles"]) for r in order]
    v = [int(r["vonneumann_cycles"]) for r in order]
    fig, ax = plt.subplots(figsize=(8, 4.2))
    x = range(len(order)); w = 0.36
    ax.bar([i - w / 2 - 0.01 for i in x], h, w, color=BLUE, label="Harvard (split I/D)")
    ax.bar([i + w / 2 + 0.01 for i in x], v, w, color=ORANGE, label="Von Neumann (unified)")
    for i, r in enumerate(order):
        ax.text(i + w / 2 + 0.01, v[i] + 12, f'{float(r["speedup"]):.2f}x', ha="center",
                fontsize=9, color=INK)
    ax.set_xticks(list(x)); ax.set_xticklabels(names, fontsize=9)
    ax.set_ylabel("Clock cycles to completion")
    ax.spines[["top", "right"]].set_visible(False)
    ax.yaxis.grid(True, color=GRID, lw=0.8); ax.set_axisbelow(True)
    ax.legend(frameon=False, loc="upper left")
    ax.set_title("Cycles per program (label = Harvard speed-up)", loc="left", fontsize=11, color=INK)
    fig.savefig(os.path.join(FIG, "cycles_comparison.png"), dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)


if __name__ == "__main__":
    block_harvard()
    block_vonneumann()
    waveform("harvard", BLUE, "Harvard - vector_add loop: every load/store overlaps an instruction fetch (no stalls)")
    waveform("vonneumann", ORANGE, "Von Neumann - same loop: each load/store steals the bus for one extra cycle")
    cycles_chart()
    print("figures written to", FIG)
