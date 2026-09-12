#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 jsDelivr 拉 GitHub 版 NiuTrans 语料（v2：并发 16，已下过的自动跳过）。"""

import concurrent.futures as cf
import os
import subprocess
import time
import urllib.parse

import pandas as pd

OUT = "/tmp/gh_corpus"
CDN = [
    "https://cdn.jsdelivr.net/gh/NiuTrans/Classical-Modern@main/",
    "https://fastly.jsdelivr.net/gh/NiuTrans/Classical-Modern@main/",
    "https://gcore.jsdelivr.net/gh/NiuTrans/Classical-Modern@main/",
]
WORKERS = 16

df = pd.read_parquet("/tmp/cm.parquet", columns=["info"])
infos = sorted(set(df["info"].astype(str)))


def to_path(info):
    seg = info.strip("《》").split("·")
    book, rest = seg[0], seg[1:]
    if not rest:
        return None
    return "/".join(["双语数据", book] + rest + ["bitext.txt"])


def safe_name(info):
    return info.strip("《》").replace("·", "_")


jobs = [(i, p) for i, p in ((i, to_path(i)) for i in infos) if p]
os.makedirs(OUT, exist_ok=True)
todo = [j for j in jobs
        if not (os.path.exists(os.path.join(OUT, safe_name(j[0]) + ".txt"))
                and os.path.getsize(os.path.join(OUT, safe_name(j[0]) + ".txt")) > 0)]
print("待抓 %d 个（总 %d）" % (len(todo), len(jobs)), flush=True)


def fetch(job):
    info, path = job
    dst = os.path.join(OUT, safe_name(info) + ".txt")
    enc = urllib.parse.quote(path, safe="/")
    for base in CDN:
        p = subprocess.run(["curl", "-4", "-sS", "-L", "--max-time", "30", "-o", dst,
                            "-w", "%{http_code}", base + enc], capture_output=True)
        if p.stdout.decode().strip() == "200" and os.path.exists(dst) and os.path.getsize(dst) > 0:
            return "ok", info
        if os.path.exists(dst) and os.path.getsize(dst) == 0:
            os.remove(dst)
    return "fail", info


t0 = time.time()
ok = fail = 0
fails = []
with cf.ThreadPoolExecutor(max_workers=WORKERS) as ex:
    futs = [ex.submit(fetch, j) for j in todo]
    for i, f in enumerate(cf.as_completed(futs), 1):
        status, info = f.result()
        if status == "ok":
            ok += 1
        else:
            fail += 1
            fails.append(info)
        if i % 500 == 0:
            print("  %d/%d  新下 %d 失败 %d  %.0fs" % (i, len(todo), ok, fail, time.time() - t0), flush=True)

print("完成：新下 %d，失败 %d，用时 %.0f 秒" % (ok, fail, time.time() - t0))
if fails:
    with open("/tmp/gh_fails.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(fails))
    print("失败样例：", fails[:10])
