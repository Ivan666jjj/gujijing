# 古籍镜（GuJiJing）

一个 macOS 古籍阅读器：直接抓[汉典古籍](https://gj.zdic.net)的正文，选中一段就能看白话译文。
纯 Swift + AppKit，没有第三方依赖，`swiftc` 直接编译。

## 特性

- **经史子集浏览**：按「部 → 书 → 篇」逐层翻，正文支持繁→简一键切换
- **选段即译**：选中正文点「译」，走两级——
  1. **本地语料库**（离线、免费、毫秒级）：97 本古籍、近百万句对，随 App 打包，**不需要任何 API key**，
     dmg 发给别人也能直接用
  2. **DeepSeek 在线翻译**：本地没收录时才走这里（需要在 `~/.reasonix/.env` 里配 `DEEPSEEK_API_KEY`），
     结果会缓存到 `~/Library/Caches/古籍镜/translations.plist`，同一段不重复花钱
- **双击查字形**：正文里双击任意一个字，拉起「字源镜」看它的字形演变
- **韵典**：内置韵书数据，按韵部查字

## 编译

```bash
bash build.sh          # 编译并打包，输出到桌面：古籍镜.app 与 古籍镜-1.0.dmg
bash build.sh /tmp/out # 也可以指定输出目录
```

## 语料

译文语料来自 [NiuTrans/Classical-Modern](https://github.com/NiuTrans/Classical-Modern)
（东北大学小牛翻译团队开源，MIT 协议）——97 本书、972,467 个句对。

语料**不随仓库分发**（160 MB+），clone 之后自己生成，结果写到 `corpus/`，
`build.sh` 会自动把它打进 `.app`：

```bash
# 方式一（快，推荐）：从 Hugging Face 镜像一次拉全
python3 tools/build_corpus.py

# 方式二（更全更新）：从 GitHub 原仓库逐篇拉最新版，再和镜像版合并
python3 tools/fetch_github_corpus.py     # 约 7300 个文件，10~25 分钟
python3 tools/build_corpus_github.py
python3 tools/merge_corpus.py            # 用镜像版补 GitHub 版没拉到的篇章
```

两种方式都依赖 `pip install pandas pyarrow`。

### 命中率怎么测

```bash
python3 tools/fetch_zdic_pages.py                    # 抓汉典真实正文当测试集
mkdir -p /tmp/eval && ln -sfn "$PWD/corpus" /tmp/eval/corpus
swiftc -swift-version 5 -o /tmp/eval/corpus_eval \
  tools/eval/main.swift Translate.swift Core.swift -framework AppKit
python3 tools/eval_hit_rate.py /tmp/eval/corpus_eval
```

当前实测（汉典《论语》8 篇 +《孟子》4 篇，441 段真实正文，繁体带「」引号、含异体字与校勘注文）：

| | 全命中 | 部分命中 | 零命中 |
|---|---|---|---|
| 最初版 | 72.6% | 86 段 | 35 段 |
| 现在 | **81.0%** | 54 段 | 30 段 |

匹配时做的事，都写在 `Translate.swift` 的 `LocalCorpus` 里：

- 繁体→简体转换；再归并一批**老异体字**（`愼→慎`、`喩→喻`、`攷→考`…共 53 条，繁简转换管不到）
- **剔除校勘注文**（汉典正文里的「一作『也已矣』」「一無『已』字」不是正文）
- 只留汉字/字母/数字，抹掉空白和标点（汉典和语料的标点习惯不一样）
- 切句时空壳丢掉（`子曰：「学而时习之…」` 收尾的 `」` 会被切成一段只剩标点的碎片）
- 整句对不上时退一步做包含匹配，只有唯一候选才采用，并在界面上标「近似匹配，请核对」
- 只命中一部分也先把本地译文给出来，标明「只收录了 N 句中的 M 句」

## 已知限制

- 语料是爬取后自动做句对齐的，个别地方有错位；上游还有少量错字
  （比如《孟子》「人之**患**在好为人师」在语料里写成「人之**忌**」）
- 只覆盖这 97 本，汉典里其它书只显示原文
- 没做 Apple 开发者签名（ad-hoc 签名），别人首次打开要在
  「系统设置 → 隐私与安全性」里点一下「仍要打开」

## 协议

代码 MIT。语料版权见上游项目（同样 MIT）。
