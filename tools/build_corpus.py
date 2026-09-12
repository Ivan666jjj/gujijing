#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 HF 镜像的全量语料（972,467 句 / 97 本）拆成「每本一个 json」，
给 App 做按书懒加载，另外合并一个 `_common.json` 放所有小型经典当兜底。

每个文件结构（尽量紧凑）：
{
  "i": {"规范化古文句": 下标},
  "t": ["现代文译文", ...]
}
古文句做了「去空白 + 去标点」规范化，查询侧同样处理。
"""

import json
import os
import re

import pandas as pd

OUT = os.path.expanduser("~/Desktop/古籍镜-源码/corpus")
COMMON_MAX = 200_000          # 字数低于这个数的书进「常用小书」合集

KEEP = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fffA-Za-z0-9]")


def norm(s):
    return "".join(KEEP.findall(str(s)))


def build(rows):
    keys, texts = {}, []
    for cls, mod in rows:
        k = norm(cls)
        m = str(mod).strip()
        if len(k) < 2 or not m:
            continue
        if k in keys:
            continue
        keys[k] = len(texts)
        texts.append(m)
    return keys, texts


def dump(path, keys, texts):
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"i": keys, "t": texts}, f, ensure_ascii=False, separators=(",", ":"))
    return os.path.getsize(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    df = pd.read_parquet("/tmp/cm.parquet", columns=["info", "classical", "modern"])
    df["book"] = df["info"].str.extract(r"^《([^·》]+)")[0].fillna("其他")
    df["chars"] = df["classical"].str.len().fillna(0) + df["modern"].str.len().fillna(0)

    book_chars = df.groupby("book")["chars"].sum()
    common_books = set(book_chars[book_chars < COMMON_MAX].index)
    print("总书数 %d，其中 %d 本会并入 _common 兜底合集" % (len(book_chars), len(common_books)))

    total = 0
    manifest = []
    for book, g in df.groupby("book"):
        keys, texts = build(zip(g["classical"], g["modern"]))
        if not keys:
            continue
        safe = re.sub(r"[\\/:*?\"<>|]", "_", book)
        size = dump(os.path.join(OUT, safe + ".json"), keys, texts)
        total += size
        manifest.append({"book": book, "file": safe + ".json", "n": len(texts)})
        print("  %-12s %7d 句  %6.1f MB" % (book, len(texts), size / 1e6))

    cdf = df[df["book"].isin(common_books)]
    keys, texts = build(zip(cdf["classical"], cdf["modern"]))
    size = dump(os.path.join(OUT, "_common.json"), keys, texts)
    total += size
    manifest.append({"book": "_common", "file": "_common.json", "n": len(texts)})
    print("  %-12s %7d 句  %6.1f MB（小书合集）" % ("_common", len(texts), size / 1e6))

    with open(os.path.join(OUT, "_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(sorted(manifest, key=lambda x: -x["n"]), f, ensure_ascii=False, indent=1)

    print("合计 %.1f MB，落在 %s" % (total / 1e6, OUT))


if __name__ == "__main__":
    main()
