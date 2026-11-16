#!/usr/bin/env python3
"""
rv32_asm.py - Tiny two-pass assembler + golden-model ISS for the RV32I subset
used in Project 9 (Instruction and Data Memory Hierarchy).

Usage:
    python3 rv32_asm.py <prog.s> <out_dir>

Produces in <out_dir>:
    <name>.hex          instruction memory image (one 32-bit word per line)
    <name>_data.hex     initial data memory image (from .data section)
    <name>_expect.hex   expected FINAL data memory image (from the ISS)
    <name>_model.json   golden-model statistics + predicted cycle counts

Assembly syntax (subset):
    .text / .data             section switch (.data is placed at 0x1000)
    label:                    labels
    .word v1, v2, ...         data words
    add/sub/and/or/xor/slt/sll/srl   rd, rs1, rs2
    addi/andi/ori/xori/slti/slli/srli rd, rs1, imm
    lw rd, off(rs1)   sw rs2, off(rs1)
    beq/bne/blt/bge rs1, rs2, label
    jal rd, label     jalr rd, off(rs1)    lui rd, imm20
    pseudo: nop, li rd, imm, mv rd, rs, j label, la rd, label, halt
"""
import json
import os
import re
import sys

DMEM_BASE = 0x1000
IO_BASE = 0x2000
IMEM_WORDS = 1024
DMEM_WORDS = 1024

ABI = {"zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4, "t0": 5, "t1": 6, "t2": 7,
       "s0": 8, "fp": 8, "s1": 9, "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14,
       "a5": 15, "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21,
       "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27, "t3": 28,
       "t4": 29, "t5": 30, "t6": 31}

R_OPS = {"add": (0, 0), "sub": (0, 0x20), "sll": (1, 0), "slt": (2, 0),
         "xor": (4, 0), "srl": (5, 0), "or": (6, 0), "and": (7, 0)}
I_OPS = {"addi": 0, "slti": 2, "xori": 4, "ori": 6, "andi": 7, "slli": 1, "srli": 5}
B_OPS = {"beq": 0, "bne": 1, "blt": 4, "bge": 5}


def reg(tok):
    tok = tok.strip()
    if tok in ABI:
        return ABI[tok]
    m = re.fullmatch(r"x(\d+)", tok)
    if not m or int(m.group(1)) > 31:
        raise ValueError(f"bad register '{tok}'")
    return int(m.group(1))


def num(tok):
    return int(tok.strip(), 0)


def u32(v):
    return v & 0xFFFFFFFF


def s32(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


# ----------------------------------------------------------------- encoders
def enc_r(f7, rs2, rs1, f3, rd, op=0x33):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3=2, op=0x23):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_b(imm, rs2, rs1, f3, op=0x63):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | op


def enc_j(imm, rd, op=0x6F):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | \
           (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | op


def enc_u(imm20, rd, op=0x37):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


# ----------------------------------------------------------------- assembler
def expand_pseudo(mn, ops):
    """Return list of (mnemonic, operands) real instructions."""
    if mn == "nop":
        return [("addi", ["x0", "x0", "0"])]
    if mn == "mv":
        return [("addi", [ops[0], ops[1], "0"])]
    if mn == "j":
        return [("jal", ["x0", ops[0]])]
    if mn == "halt":                       # store to IO HALT register
        return [("lui", ["x31", str(IO_BASE >> 12)]), ("sw", ["x0", "4(x31)"])]
    if mn in ("li", "la"):
        return [("__li", ops)]             # always 2 words (lui + addi)
    return [(mn, ops)]


def assemble(path):
    text, data = [], []
    labels = {}
    section = "text"
    # ---------- pass 1: layout
    for lineno, raw in enumerate(open(path), 1):
        line = raw.split("#")[0].strip()
        if not line:
            continue
        while ":" in line:
            lab, line = line.split(":", 1)
            labels[lab.strip()] = (len(text) * 4) if section == "text" else DMEM_BASE + len(data) * 4
            line = line.strip()
        if not line:
            continue
        if line in (".text", ".data"):
            section = line[1:]
            continue
        parts = line.split(None, 1)
        mn = parts[0].lower()
        ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
        if mn == ".word":
            data.extend(ops)
            continue
        if mn == ".space":
            data.extend(["0"] * (num(ops[0]) // 4))
            continue
        for item in expand_pseudo(mn, ops):
            if item[0] == "__li":
                text.append(("__lui_hi", item[1], lineno))
                text.append(("__addi_lo", item[1], lineno))
            else:
                text.append((item[0], item[1], lineno))

    def val(tok):
        tok = tok.strip()
        return labels[tok] if tok in labels else num(tok)

    # ---------- pass 2: encode
    words = []
    for idx, (mn, ops, lineno) in enumerate(text):
        pc = idx * 4
        try:
            if mn == "__lui_hi":
                v = u32(val(ops[1]))
                hi = ((v + 0x800) >> 12) & 0xFFFFF
                w = enc_u(hi, reg(ops[0]))
            elif mn == "__addi_lo":
                v = u32(val(ops[1]))
                lo = v & 0xFFF
                w = enc_i(lo, reg(ops[0]), 0, reg(ops[0]), 0x13)
            elif mn in R_OPS:
                f3, f7 = R_OPS[mn]
                w = enc_r(f7, reg(ops[2]), reg(ops[1]), f3, reg(ops[0]))
            elif mn in I_OPS:
                imm = val(ops[2])
                if mn in ("slli", "srli"):
                    imm &= 0x1F
                w = enc_i(imm, reg(ops[1]), I_OPS[mn], reg(ops[0]), 0x13)
            elif mn in ("lw", "sw", "jalr"):
                if mn == "jalr" and "(" not in ops[1]:
                    off, base = "0", ops[1]
                else:
                    m = re.fullmatch(r"(-?\w*)\((\w+)\)", ops[1].replace(" ", ""))
                    off, base = (m.group(1) or "0"), m.group(2)
                if mn == "lw":
                    w = enc_i(val(off), reg(base), 2, reg(ops[0]), 0x03)
                elif mn == "sw":
                    w = enc_s(val(off), reg(ops[0]), reg(base))
                else:
                    w = enc_i(val(off), reg(base), 0, reg(ops[0]), 0x67)
            elif mn in B_OPS:
                w = enc_b(val(ops[2]) - pc, reg(ops[1]), reg(ops[0]), B_OPS[mn])
            elif mn == "jal":
                if len(ops) == 1:
                    ops = ["ra", ops[0]]
                w = enc_j(val(ops[1]) - pc, reg(ops[0]))
            elif mn == "lui":
                w = enc_u(val(ops[1]), reg(ops[0]))
            else:
                raise ValueError(f"unknown mnemonic '{mn}'")
        except Exception as e:
            raise SystemExit(f"{path}:{lineno}: {e}")
        words.append(u32(w))
    dwords = [u32(val(d)) for d in data]
    src_lines = open(path).read().splitlines()
    listing = [(i * 4, words[i], src_lines[ln - 1].split("#")[0].split(":")[-1].strip())
               for i, (_, _, ln) in enumerate(text)]
    return words, dwords, labels, listing


# ----------------------------------------------------------------- golden ISS
def simulate(code, data, max_steps=200000):
    imem = code + [0x13] * (IMEM_WORDS - len(code))
    dmem = data + [0] * (DMEM_WORDS - len(data))
    x = [0] * 32
    pc = 0
    st = {"instret": 0, "loads": 0, "stores": 0, "branches": 0, "taken": 0,
          "jumps": 0, "alu": 0, "out": []}

    def daddr(a):
        a = u32(a)
        if DMEM_BASE <= a < DMEM_BASE + DMEM_WORDS * 4:
            return ("d", (a - DMEM_BASE) >> 2)
        if IO_BASE <= a < IO_BASE + 0x100:
            return ("io", a - IO_BASE)
        raise RuntimeError(f"bus error at 0x{a:08x}, pc=0x{pc:08x}")

    for _ in range(max_steps):
        ins = imem[(pc >> 2) % IMEM_WORDS]
        op = ins & 0x7F
        rd = (ins >> 7) & 31
        f3 = (ins >> 12) & 7
        rs1 = (ins >> 15) & 31
        rs2 = (ins >> 20) & 31
        f7 = ins >> 25
        immi = s32(ins) >> 20
        imms = ((s32(ins) >> 25) << 5) | ((ins >> 7) & 31)
        immb = ((s32(ins) >> 31) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1)
        immj = ((s32(ins) >> 31) << 20) | (((ins >> 12) & 0xFF) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1)
        a, b = x[rs1], x[rs2]
        npc = u32(pc + 4)
        res = None
        st["instret"] += 1

        def alu(f3, a, b, sub):
            if f3 == 0: return u32(a - b) if sub else u32(a + b)
            if f3 == 1: return u32(a << (b & 31))
            if f3 == 2: return 1 if s32(a) < s32(b) else 0
            if f3 == 4: return a ^ b
            if f3 == 5: return a >> (b & 31)
            if f3 == 6: return a | b
            if f3 == 7: return a & b
            raise RuntimeError("bad f3")

        if op == 0x33:
            res = alu(f3, a, b, f7 == 0x20); st["alu"] += 1
        elif op == 0x13:
            res = alu(f3, a, u32(immi), False); st["alu"] += 1
        elif op == 0x37:
            res = u32(ins & 0xFFFFF000); st["alu"] += 1
        elif op == 0x03:
            st["loads"] += 1
            kind, i = daddr(a + immi)
            res = dmem[i] if kind == "d" else 0
        elif op == 0x23:
            st["stores"] += 1
            kind, i = daddr(a + imms)
            if kind == "d":
                dmem[i] = b
            elif i == 0:
                st["out"].append(b)
            elif i == 4:
                return dmem, st
        elif op == 0x63:
            st["branches"] += 1
            take = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b)}[f3]
            if take:
                st["taken"] += 1
                npc = u32(pc + immb)
        elif op == 0x6F:
            st["jumps"] += 1; res = npc; npc = u32(pc + immj)
        elif op == 0x67:
            st["jumps"] += 1; res = npc; npc = u32(a + immi) & ~1
        else:
            raise RuntimeError(f"illegal instr 0x{ins:08x} at 0x{pc:08x}")
        if res is not None and rd:
            x[rd] = res
        pc = npc
    raise RuntimeError("program did not halt")


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    name = os.path.splitext(os.path.basename(src))[0]
    code, data, labels, listing = assemble(src)
    final, st = simulate(code, data)
    mem_ops = st["loads"] + st["stores"]
    st.update({
        "program": name,
        "code_words": len(code),
        "data_words": len(data),
        "mem_fraction": round(mem_ops / st["instret"], 4),
        "pred_cycles_harvard": st["instret"],            # CPI = 1
        "pred_cycles_vonneumann": st["instret"] + mem_ops,  # +1 per ld/st
    })
    with open(f"{out}/{name}.hex", "w") as f:
        f.write("\n".join(f"{w:08x}" for w in code) + "\n")
    with open(f"{out}/{name}_data.hex", "w") as f:
        f.write("\n".join(f"{w:08x}" for w in (data or [0])) + "\n")
    with open(f"{out}/{name}_expect.hex", "w") as f:
        f.write("\n".join(f"{w:08x}" for w in final) + "\n")
    with open(f"{out}/{name}.lst", "w") as f:
        for pc, w, txt in listing:
            f.write(f"{pc:08x}  {w:08x}  {txt}\n")
    with open(f"{out}/{name}_model.json", "w") as f:
        json.dump(st, f, indent=2)
    print(f"[asm] {name}: {len(code)} instr words, {len(data)} data words, "
          f"instret={st['instret']}, ld={st['loads']}, st={st['stores']}, "
          f"pred H={st['pred_cycles_harvard']} VN={st['pred_cycles_vonneumann']}")


if __name__ == "__main__":
    main()
