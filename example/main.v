module main

// main.v — 示例应用的唯一入口
//
// 整个示例的业务代码都在 app/ 子模块里（bootstrap、服务、控制器、中间件）。
// V 的 v run main.v 是单文件模式，只会编译这个文件 + 它 import 的模块；
// 把业务放进 app/ 后，v -enable-globals run main.v 和 v -enable-globals run .
// 两种写法都能用，不需要记「必须按目录编译」这个隐藏规则。
import app

fn main() {
	app.run()
}
