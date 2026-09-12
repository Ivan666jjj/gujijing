#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓几篇汉典（gj.zdic.net）的真实正文当测试集，保存到 /tmp/zdic_pages/<篇名>.json"""

import html
import json
import os
import re
import subprocess
import time

OUT = "/tmp/zdic_pages"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")

# (书路径, 篇目列表页, 最多抓几篇)
TARGETS = [
    ("經部/論語", "https://gj.zdic.net/jingbu/44/", 8, "論語"),
    ("經部/孟子", "https://gj.zdic.net/jingbu/52/", 4, "孟子"),
]


def curl(url):
    p = subprocess.run(["curl", "-4", "-sS", "-L", "--max-time", "25", "-A", UA, url],
                       capture_output=True)
    return p.stdout.decode("utf-8", "replace")


def paras(page_html):
    i = page_html.find("article-body")
    body = page_html[i:i + 60000] if i > 0 else page_html
    out = []
    for p in re.findall(r"<p[^>]*>(.*?)</p>", body, re.S):
        s = html.unescape(re.sub(r"<[^>]+>", "", p)).strip()
        if len(s) >= 6:      # 太短的碎片（含 JS 残渣）不要
            out.append(s)
    return out


os.makedirs(OUT, exist_ok=True)
summary = []
for label, list_url, limit, book in TARGETS:
    listing = curl(list_url)
    links = []
    for m in re.finditer(r'href="(/jingbu/\d+/\d+\.html)"[^>]*title="([^"]*)"', listing):
        if (m.group(1), m.group(2)) not in links:
            links.append((m.group(1), m.group(2)))
    print("%s：目录 %d 篇，抓前 %d 篇" % (label, len(links), min(limit, len(links))))
    for path, title in links[:limit]:
        page = curl("https://gj.zdic.net" + path)
        ps = paras(page)
        name = re.sub(r"[^\w\u4e00-\u9fff]", "", title)
        with open(os.path.join(OUT, "%s_%s.json" % (book, name)), "w", encoding="utf-8") as f:
            json.dump({"book": book, "title": title, "paras": ps}, f, ensure_ascii=False)
        print("   %-12s %2d 段" % (title, len(ps)))
        summary.append({"book": book, "title": title, "file": "%s_%s.json" % (book, name), "n": len(ps)})
        time.sleep(0.3)

with open(os.path.join(OUT, "_index.json"), "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=1)
print("共 %d 篇，落在 %s" % (len(summary), OUT))
