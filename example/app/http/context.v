module http

// Context — 请求上下文
//
// 直接用 photon.web.RouterContext 的别名：它直接嵌入 veb.Context，
// V 0.5.2 的 checker 只认一层嵌入；再包一层 struct 会被误判成非 veb
// 上下文，给每个返回 veb.Result 的控制器方法注入多余的 ctx 参数。
import photon.web

pub type Context = web.RouterContext
