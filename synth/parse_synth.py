#!/usr/bin/env python3
"""parse_synth.py - turn Yosys 'stat' / 'ltp' output into docs/synth.csv."""
import csv
import os
import re
import sys

logs, out_csv = sys.argv[1], sys.argv[2]
rows = []
for name in ("harvard", "vonneumann", "split", "unified", "l1_cache_256B"):
    stat = open(os.path.join(logs, name + ".stat")).read()
    cells = {m.group(2): int(m.group(1)) for m in re.finditer(r"^\s+(\d+)\s+(?:[\d.]+\s+)?\$?(\S+)\s*$", stat, re.M)}
    if not cells:  # older yosys format: "     CELL   count"
        cells = {m.group(1): int(m.group(2)) for m in re.finditer(r"^\s+(\S+)\s+(\d+)\s*$", stat, re.M)}
    lut = sum(v for k, v in cells.items() if re.fullmatch(r"LUT[1-6]", k))
    ff = sum(v for k, v in cells.items() if re.fullmatch(r"FD[A-Z]*", k))
    lutram = sum(v for k, v in cells.items() if k.startswith("RAM") and not k.startswith("RAMB"))
    bram = sum(v for k, v in cells.items() if k.startswith("RAMB"))
    carry = cells.get("CARRY4", 0)
    mux = sum(v for k, v in cells.items() if k.startswith("MUXF"))
    ltp = open(os.path.join(logs, name + ".ltp")).read()
    m = re.search(r"Longest topological path in \S+ \(length=(\d+)\)", ltp)
    depth = int(m.group(1)) if m else -1
    rows.append({"design": name, "LUT": lut, "FF": ff, "LUTRAM": lutram, "BRAM": bram,
                 "CARRY4": carry, "MUXF": mux, "logic_depth": depth})
with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
print("%-15s %6s %6s %7s %5s %7s %6s" % ("design", "LUT", "FF", "LUTRAM", "BRAM", "CARRY4", "depth"))
for r in rows:
    print("%-15s %6d %6d %7d %5d %7d %6d" % (r["design"], r["LUT"], r["FF"], r["LUTRAM"],
                                            r["BRAM"], r["CARRY4"], r["logic_depth"]))
