#!/usr/bin/env python3
"""
cache_model.py - Golden model of the Phase II L1 caches (rtl/l1_cache.v).

Replays the memory-access trace produced by the ISS (rv32_asm.simulate) through
direct-mapped, write-through, no-write-allocate caches and counts the events
that the hardware performance counters (rtl/hier_perf.v) report. Because the
caches are direct-mapped and never allocate on a write, the hit/miss sequence
depends only on the access order, not on timing - so the hardware counts must
match this model EXACTLY.

    arch = "split"   : I-fetches -> I-cache, loads/stores -> D-cache
    arch = "unified" : every access -> one shared cache (fetch, then data)
    nocache = True   : every read is a miss (flat memory)

Usage as a script:
    python3 cache_model.py prog.s [split|unified] [sets] [line_words]
"""
import os
import sys


class DirectMapped:
    def __init__(self, sets, line_words, nocache=False):
        self.sets, self.line, self.nocache = sets, line_words, nocache
        self.tags = [None] * sets

    def _split(self, addr):
        w = addr >> 2
        return (w // self.line) % self.sets, w // (self.line * self.sets)

    def present(self, addr):
        idx, tag = self._split(addr)
        return (not self.nocache) and self.tags[idx] == tag

    def read(self, addr):
        """returns True on hit; allocates the line on a miss"""
        if self.present(addr):
            return True
        if not self.nocache:
            idx, tag = self._split(addr)
            self.tags[idx] = tag
        return False


def run(trace, arch="split", sets=16, line_words=4, nocache=False):
    st = dict(i_reads=0, i_misses=0, d_reads=0, d_misses=0, d_writes=0, d_write_hits=0)
    if arch == "split":
        ic = DirectMapped(sets, line_words, nocache)
        dc = DirectMapped(sets, line_words, nocache)
    else:
        ic = dc = DirectMapped(sets, line_words, nocache)
    for kind, addr in trace:
        if kind == "I":
            st["i_reads"] += 1
            st["i_misses"] += not ic.read(addr)
        elif kind == "R":
            st["d_reads"] += 1
            st["d_misses"] += not dc.read(addr)
        else:                                   # write-through, no allocate
            st["d_writes"] += 1
            st["d_write_hits"] += dc.present(addr)
    return st


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import rv32_asm
    src = sys.argv[1]
    arch = sys.argv[2] if len(sys.argv) > 2 else "split"
    sets = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    line = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    code, data, _, _ = rv32_asm.assemble(src)
    tr = []
    rv32_asm.simulate(code, data, trace=tr)
    print(run(tr, arch, sets, line))
