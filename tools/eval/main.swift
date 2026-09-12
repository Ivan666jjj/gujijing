import Foundation

// 评估用：corpus_eval <书名> <段落...>
// 每行输出「命中句数/总句数<TAB>段落」，交给 python 统计。

let args = Array(CommandLine.arguments.dropFirst())
guard let book = args.first else { exit(1) }
let paras = Array(args.dropFirst())

LocalCorpus.prepare(book: book)
for p in paras {
    let hit = LocalCorpus.lookup(p)
    print("\(hit.matched)/\(hit.total)\t\(p)")
}
