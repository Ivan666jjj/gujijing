#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 GitHub 版（2024 修复版）语料编成 App 用的按书索引。

输入：/tmp/gh_corpus/<书>_<篇>_<节>.txt（每份是一串「古文：…／现代文：…」块）
输出：/tmp/corpus_gh/<书>.json + _common.json
结构 {"i": {规范化古文: 下标}, "t": [译文, ...]}

比 HF 版多做两件事：
1. 块内句数相等时拆成单句键，选一句也能精确命中；
2. 句数不等时让每个单句都指向整块译文（弱映射），提高短句命中率。
"""

import json
import os
import re

SRC = "/tmp/gh_corpus"
OUT = "/tmp/corpus_gh"
COMMON_MAX = 200_000          # 字数低于这个数的书，额外并进 _common 兜底合集

SENT_RE = re.compile(r"[^。！？]*[。！？]")
KEEP_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fffA-Za-z0-9]")


def norm(s):
    return "".join(KEEP_RE.findall(str(s)))


def split_sents(s):
    s = str(s).strip()
    if not s:
        return []
    parts = SENT_RE.findall(s)
    rest = s[len("".join(parts)):].strip()
    if rest:
        parts.append(rest)
    return [p.strip() for p in parts if p.strip()]


def parse_bitext(text):
    """→ [(古文块, 现代文块), ...]"""
    blocks = []
    orig, trans, mode = [], [], None

    def flush():
        nonlocal orig, trans, mode
        if orig and trans:
            blocks.append(("".join(orig).strip(), "".join(trans).strip()))
        orig, trans, mode = [], [], None

    for raw in text.splitlines():
        ln = raw.strip()
        if not ln:
            flush()
            continue
        if ln.startswith("古文："):
            flush()
            orig, mode = [ln[len("古文："):]], "o"
        elif ln.startswith("现代文："):
            trans, mode = [ln[len("现代文："):]], "t"
        elif mode == "o":
            orig.append(ln)
        elif mode == "t":
            trans.append(ln)
    flush()
    return blocks


def main():
    books = {}          # 书名 -> (keys, texts)
    nfile = nblock = 0

    for name in sorted(os.listdir(SRC)):
        if not name.endswith(".txt"):
            continue
        book = name[:-4].split("_")[0]
        try:
            text = open(os.path.join(SRC, name), encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        blocks = parse_bitext(text)
        if not blocks:
            continue
        nfile += 1
        keys, texts = books.setdefault(book, ({}, []))

        for o, t in blocks:
            ko = norm(o)
            if len(ko) < 2 or len(norm(t)) < 2:
                continue

            if ko in keys:
                block_idx = keys[ko]
            else:
                block_idx = len(texts)
                keys[ko] = block_idx
                texts.append(t)
                nblock += 1

            os_, ts = split_sents(o), split_sents(t)
            if len(os_) == len(ts) and len(os_) > 1:
                for so, st in zip(os_, ts):
                    k = norm(so)
                    if len(k) < 4 or k in keys:
                        continue
                    keys[k] = len(texts)
                    texts.append(st.strip())
            else:
                for so in os_:
                    k = norm(so)
                    if len(k) < 4 or k in keys:
                        continue
                    keys[k] = block_idx        # 该句没单独译文，指向整块

    os.makedirs(OUT, exist_ok=True)
    total = 0
    sized = []
    for book, (keys, texts) in sorted(books.items()):
        safe = re.sub(r"[\\/:*?\"<>|]", "_", book)
        p = os.path.join(OUT, safe + ".json")
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"i": keys, "t": texts}, f, ensure_ascii=False, separators=(",", ":"))
        sz = os.path.getsize(p)
        total += sz
        chars = sum(len(t) for t in texts) + sum(len(k) for k in keys)
        sized.append((book, len(texts), chars, sz))

    small = [b for b, n, c, s in sized if c < COMMON_MAX]
    ck, ct = {}, []
    for book in small:
        keys, texts = books[book]
        for k, i in keys.items():
            if k in ck:
                continue
            ck[k] = len(ct)
            ct.append(texts[i])
    p = os.path.join(OUT, "_common.json")
    with open(p, "w", encoding="utf-8") as f:
        json.dump({"i": ck, "t": ct}, f, ensure_ascii=False, separators=(",", ":"))
    total += os.path.getsize(p)

    print("读了 %d 个文件 / %d 个整块；%d 本书" % (nfile, nblock, len(books)))
    print("_common 收了 %d 本小书 / %d 条" % (len(small), len(ct)))
    print("合计 %.1f MB，输出到 %s" % (total / 1e6, OUT))
    print()
    print("条目最多的 10 本：")
    for b, n, c, s in sorted(sized, key=lambda x: -x[1])[:10]:
        print("   %-14s %7d 条  %6.1f MB" % (b, n, s / 1e6))


if __name__ == "__main__":
    main()
