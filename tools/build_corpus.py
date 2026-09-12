#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 App 用的本地译文语料（方式一：从 Hugging Face 镜像一次拉全）。

语料来自 NiuTrans/Classical-Modern（MIT）的 Hugging Face 镜像
xmj2002/Chinese_modern_classical：97 本书 / 972,467 个句对。

做法：每一本书拆成一个 JSON，App 读到哪本才加载哪本；
另外把所有「小书」并进 _common.json 当兜底。

每个文件结构（尽量紧凑）：
    {"i": {"规范化古文句": 下标}, "t": ["现代文译文", ...]}
古文句做了「去空白 + 去标点」归一化，查询侧同样处理。

用法：
    pip install pandas pyarrow
    python3 tools/build_corpus.py            # 输出到 <仓库>/corpus/
"""

import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "corpus")
PARQUET = "/tmp/Chinese_modern_classical.parquet"
PARQUET_URL = ("https://hf-mirror.com/datasets/xmj2002/Chinese_modern_classical"
               "/resolve/main/data/train-00000-of-00001-a082a3e0459a7949.parquet")
COMMON_MAX = 200_000          # 字数低于这个数的书进「常用小书」合集

KEEP = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fffA-Za-z0-9]")


def norm(s):
    return "".join(KEEP.findall(str(s)))


def ensure_parquet():
    if os.path.exists(PARQUET) and os.path.getsize(PARQUET) > 100_000_000:
        print("复用已下载的 %s" % PARQUET)
        return
    print("下载原始数据（约 123 MB）…")
    subprocess.run(["curl", "-L", "-sS", "-C", "-", "--max-time", "3600",
                    "-o", PARQUET, PARQUET_URL], check=True)


def build(rows):
    keys, texts = {}, []
    for cls, mod in rows:
        k = norm(cls)
        m = str(mod).strip()
        if len(k) < 2 or not m or k in keys:
            continue
        keys[k] = len(texts)
        texts.append(m)
    return keys, texts


def dump(path, keys, texts):
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"i": keys, "t": texts}, f, ensure_ascii=False, separators=(",", ":"))
    return os.path.getsize(path)


def main():
    import pandas as pd

    ensure_parquet()
    os.makedirs(OUT, exist_ok=True)

    df = pd.read_parquet(PARQUET, columns=["info", "classical", "modern"])
    df["book"] = df["info"].astype(str).str.extract(r"^《([^·》]+)")[0].fillna("其他")
    df["chars"] = df["classical"].str.len().fillna(0) + df["modern"].str.len().fillna(0)

    book_chars = df.groupby("book")["chars"].sum()
    common_books = set(book_chars[book_chars < COMMON_MAX].index)
    print("共 %d 本书，其中 %d 本会并入 _common 兜底合集" % (len(book_chars), len(common_books)))

    total = 0
    for book, g in df.groupby("book"):
        keys, texts = build(zip(g["classical"], g["modern"]))
        if not keys:
            continue
        safe = re.sub(r"[\\/:*?\"<>|]", "_", book)
        size = dump(os.path.join(OUT, safe + ".json"), keys, texts)
        total += size
        print("  %-12s %7d 句  %6.1f MB" % (book, len(texts), size / 1e6))

    cdf = df[df["book"].isin(common_books)]
    keys, texts = build(zip(cdf["classical"], cdf["modern"]))
    total += dump(os.path.join(OUT, "_common.json"), keys, texts)
    print("  %-12s %7d 句（小书合集）" % ("_common", len(texts)))

    print("\n合计 %.1f MB → %s" % (total / 1e6, os.path.abspath(OUT)))


if __name__ == "__main__":
    sys.exit(main())
