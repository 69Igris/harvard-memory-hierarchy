#!/usr/bin/env python3
"""summarize.py - merge RTL PERF lines with golden-model predictions into a CSV."""
import csv
import json
import re
import sys

perf_log, build_dir, out_csv = sys.argv[1:4]
rows = {}
for line in open(perf_log):
    if not line.startswith("PERF"):
        continue
    kv = dict(re.findall(r"(\w+)=(\S+)", line))
    rows.setdefault(kv["prog"], {})[kv["arch"]] = kv

fields = ["program", "instret", "loads", "stores", "mem_fraction",
          "harvard_cycles", "vonneumann_cycles", "harvard_cpi", "vonneumann_cpi",
          "speedup", "parallel_cycles_harvard", "stall_cycles_vn",
          "model_match", "self_check"]
out = []
ok_all = True
for prog in sorted(rows):
    m = json.load(open(f"{build_dir}/{prog}_model.json"))
    h, v = rows[prog]["harvard"], rows[prog]["vonneumann"]
    hc, vc = int(h["cycles"]), int(v["cycles"])
    match = (hc == m["pred_cycles_harvard"] and vc == m["pred_cycles_vonneumann"]
             and int(h["instret"]) == m["instret"] == int(v["instret"]))
    passed = h["errors"] == "0" and v["errors"] == "0"
    ok_all &= match and passed
    out.append({
        "program": prog, "instret": m["instret"], "loads": m["loads"],
        "stores": m["stores"], "mem_fraction": m["mem_fraction"],
        "harvard_cycles": hc, "vonneumann_cycles": vc,
        "harvard_cpi": round(hc / int(h["instret"]), 3),
        "vonneumann_cpi": round(vc / int(v["instret"]), 3),
        "speedup": round(vc / hc, 3),
        "parallel_cycles_harvard": h["parallel"], "stall_cycles_vn": v["stall"],
        "model_match": "yes" if match else "NO", "self_check": "PASS" if passed else "FAIL",
    })

with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    w.writerows(out)

print("\n%-12s %7s %6s %8s %8s %6s %6s %7s %s" % ("program", "instr", "mem%", "H_cyc", "VN_cyc", "H_CPI", "VN_CPI", "speedup", "check"))
for r in out:
    print("%-12s %7d %5.1f%% %8d %8d %6.2f %6.2f %6.2fx %s/%s" % (
        r["program"], r["instret"], 100 * r["mem_fraction"], r["harvard_cycles"],
        r["vonneumann_cycles"], r["harvard_cpi"], r["vonneumann_cpi"], r["speedup"],
        r["self_check"], "model-ok" if r["model_match"] == "yes" else "MODEL-MISMATCH"))
print("\nALL TESTS PASSED" if ok_all else "\nSOME TESTS FAILED")
sys.exit(0 if ok_all else 1)
