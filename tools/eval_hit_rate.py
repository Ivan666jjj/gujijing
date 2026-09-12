#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""评估本地语料命中率（路径传参版）。

用法：python3 /tmp/eval_run.py <corpus_eval 可执行文件> [页面对照目录]
"""

import glob
import json
import os
import subprocess
import sys

TEST = sys.argv[1] if len(sys.argv) > 1 else "/tmp/eval/corpus_eval"
PAGES = sys.argv[2] if len(sys.argv) > 2 else "/tmp/zdic_pages"

total = full = partial = zero = 0
rows = []

for f in sorted(glob.glob(os.path.join(PAGES, "*.json"))):
    if os.path.basename(f).startswith("_"):
        continue
    d = json.load(open(f, encoding="utf-8"))
    book, paras = d["book"], d["paras"]
    if not paras:
        continue
    out = subprocess.run([TEST, book] + paras, capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "\t" not in line:
            continue
        frac, para = line.split("\t", 1)
        if "/" not in frac:
            continue
        m, t = (int(x) for x in frac.split("/"))
        total += 1
        if t > 0 and m == t:
            full += 1
        elif m > 0:
            partial += 1
        else:
            zero += 1
            rows.append((d["title"], para[:44]))

print("共 %d 段：全命中 %d（%.1f%%），部分命中 %d，零命中 %d"
      % (total, full, full * 100.0 / max(total, 1), partial, zero))
print()
print("— 零命中 —")
for t, p in rows[:15]:
    print("   《%s》%s" % (t, p))
