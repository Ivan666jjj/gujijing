#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""合并两版语料：GitHub 版（2024 修复版）为底，HF 版补下载失败的篇章。

输出 /tmp/corpus_final/<书>.json + _common.json，格式与 App 一致。
"""

import json
import os
import re

import pandas as pd

GH = "/tmp/corpus_gh"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "corpus")
COMMON_MAX = 200_000
KEEP = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fffA-Za-z0-9]")


def norm(s):
    return "".join(KEEP.findall(str(s)))


os.makedirs(OUT, exist_ok=True)

# ---- 1. 从 HF 数据里挑出「GitHub 没下到」的篇章 ----
fails = {x for x in open(os.path.join(HERE, "github_download_failed.txt"), encoding="utf-8").read().split("\n") if x}
df = pd.read_parquet("/tmp/Chinese_modern_classical.parquet", columns=["info", "classical", "modern"])
sub = df[df["info"].astype(str).isin(fails)]
print("要补的条目：%d（来自 %d 个失败篇章）" % (len(sub), len(fails)))

extra = {}          # 书名 -> {键: 译文}
for info, cls, mod in zip(sub["info"], sub["classical"], sub["modern"]):
    book = str(info).strip("《》").split("·")[0]
    k = norm(cls)
    t = str(mod).strip()
    if len(k) < 2 or not t:
        continue
    extra.setdefault(book, {}).setdefault(k, t)

# ---- 2. 以 GitHub 版为底，逐本合并 ----
gh_files = sorted(n for n in os.listdir(GH) if n.endswith(".json") and n != "_manifest.json")
gh_books = set()
added_total = 0
for name in gh_files:
    book = name[:-5]
    gh_books.add(book)
    d = json.load(open(os.path.join(GH, name), encoding="utf-8"))
    keys, texts = d["i"], d["t"]
    n0 = len(texts)
    for k, t in extra.get(book, {}).items():
        if k in keys:
            continue
        keys[k] = len(texts)
        texts.append(t)
    added_total += len(texts) - n0
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        json.dump({"i": keys, "t": texts}, f, ensure_ascii=False, separators=(",", ":"))
    if len(texts) - n0:
        print("   %-12s +%d 条" % (book, len(texts) - n0))

# ---- 3. GitHub 完全没有的书（整本都失败）单独补出来 ----
orphan = [b for b in extra if b not in gh_books]
for book in sorted(orphan):
    keys, texts = {}, []
    for k, t in extra[book].items():
        keys[k] = len(texts)
        texts.append(t)
    safe = re.sub(r"[\\/:*?\"<>|]", "_", book)
    with open(os.path.join(OUT, safe + ".json"), "w", encoding="utf-8") as f:
        json.dump({"i": keys, "t": texts}, f, ensure_ascii=False, separators=(",", ":"))
    print("   新建整本：《%s》%d 条" % (book, len(texts)))

# ---- 4. 重建 _common 兜底合集 ----
small_keys, small_texts = {}, []
small_books = []
for name in sorted(os.listdir(OUT)):
    if not name.endswith(".json") or name == "_common.json":
        continue
    d = json.load(open(os.path.join(OUT, name), encoding="utf-8"))
    chars = sum(len(t) for t in d["t"]) + sum(len(k) for k in d["i"])
    if chars >= COMMON_MAX:
        continue
    small_books.append(name[:-5])
    for k, i in d["i"].items():
        if k in small_keys:
            continue
        small_keys[k] = len(small_texts)
        small_texts.append(d["t"][i])
with open(os.path.join(OUT, "_common.json"), "w", encoding="utf-8") as f:
    json.dump({"i": small_keys, "t": small_texts}, f, ensure_ascii=False, separators=(",", ":"))

total = sum(os.path.getsize(os.path.join(OUT, n)) for n in os.listdir(OUT))
print()
print("补进 %d 条；_common 收了 %d 本小书 / %d 条" % (added_total, len(small_books), len(small_texts)))
print("最终 %d 个文件 / %.1f MB → %s" % (len(os.listdir(OUT)), total / 1e6, OUT))
