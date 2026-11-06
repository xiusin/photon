module strutil

// strutil.v — Photon 字符串 / 数组 / 集合工具模块入口
//
// 模块名为什么不叫 `support`
// --------------------------
// `photon.v` 声明 `module photon`，仓库根目录就是 photon 模块的目录。
// 任何叫 `support` 的顶层目录会同时被注册成两个名字：
//
//     import support          → /workspace/support
//     import photon.support   → /workspace/support
//
// 两条路径同时加载时 V 会解析到 `photon.support` 那份空的函数表，
// 报的是 `unknown function: support.snake` 这种离真因很远的错误。
// 名字不再以 `photon.` 为前缀之后，这条路彻底不存在了。
//
// 提供字符串助手（Str）、数组助手（Arr）与链式 Collection。
