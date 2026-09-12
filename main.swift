import AppKit

// 古籍镜 —— 古籍阅读（汉典古籍）+ 韵典（离线韵书）
// 入口：普通 AppKit 应用（本机只有 CommandLineTools，没有 SwiftUI 宏插件）

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
