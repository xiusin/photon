module web

// route_scan_consistency_test.v — 启动横幅上的路由表必须和真正注册的路由一致
//
// 背景：example/bootstrap.v 曾经维护一份手写端点清单，和真实路由各说各话。
// 手写清单少了整组 /__docs 路由（7 条），而它每天都被打印、每天都没人发现——
// 因为「加一条路由」和「想起去改清单」是两件互不相干的事。
//
// 去掉手写清单之后，横幅的内容完全来自 scan_controller[T]()，于是这个函数
// 的正确性就直接等于「启动时告诉你的事是否属实」。这里把两份输出对起来比：
//   - scan_controller[T]()   → 横幅里打印的（给人看）
//   - mount_controller[T,X]  → 真正注册进 RouteRegistry 的（给请求用）
// 两者但凡有一个方法只出现在一边，断言就红。
import veb

@[prefix: '/scan']
struct ScanConsistencyController {}

// 合并式属性
@[get: '/items']
pub fn (mut c ScanConsistencyController) list_items(mut ctx veb.Context, params map[string]string) veb.Result {
	return ctx.text('items')
}

// 分离式属性
@[delete]
@['/items/:id']
pub fn (mut c ScanConsistencyController) remove_item(mut ctx veb.Context, params map[string]string) veb.Result {
	return ctx.text('removed')
}

// 元组式属性
@['/items/:id'; put]
pub fn (mut c ScanConsistencyController) update_item(mut ctx veb.Context, params map[string]string) veb.Result {
	return ctx.text('updated')
}

// 无路由属性，但返回 veb.Result → 约定式路由，路径取方法名
pub fn (mut c ScanConsistencyController) convention_only(mut ctx veb.Context) veb.Result {
	return ctx.text('by convention')
}

// 只写在文档里的端点：手写清单当年就是靠这种「记得去改」维护的。
// 这里把它换成断言 —— 扫描结果里必须有 /scan 前缀下的全部四条。
fn scan_signature(routes []RouteInfo) []string {
	mut sigs := []string{}
	for r in routes {
		sigs << '${r.method} ${r.path}'
	}
	sigs.sort()
	return sigs
}

fn registry_signature(rr &RouteRegistry) []string {
	mut sigs := []string{}
	for def in rr.routes {
		sigs << '${def.method} ${def.path}'
	}
	sigs.sort()
	return sigs
}

// 带路由属性的方法：扫描结果必须和真正注册进去的一模一样。
// 这是「启动横幅是否属实」的主断言 —— 属性式路由是框架的主要用法，
// 两边的路径/方法只要有一处对不上，横幅就在骗人。
fn test_scan_controller_matches_registered_attribute_routes() {
	mut rr := new_route_registry()
	ctrl := &ScanConsistencyController{}
	rr.mount_controller[ScanConsistencyController, veb.Context](ctrl, '/scan')

	// 去掉「无属性、靠约定返回 Result」那类，只比显式声明了路由属性的
	mut scanned := []string{}
	for r in scan_controller[ScanConsistencyController]() {
		if r.path != '/scan/convention_only' {
			scanned << '${r.method} ${r.path}'
		}
	}
	scanned.sort()
	registered := registry_signature(rr)

	assert scanned == registered, '属性式路由的扫描结果与注册结果不一致: ${scanned} vs ${registered}'
}

// 已知差异（未修）：无路由属性的方法两边看法不同。
//
//   scan_controller[T]()          → 当成 GET /方法名（照 veb 的 parse_attrs 默认）
//   mount_controller[T,X]()      → 跳过，不注册
//
// 谁对取决于「框架自己的注册入口要不要和 veb 一样宽容」，这属于设计取舍，
// 不该在一条用例里替它拍板。所以这里只把差异钉成事实：一旦有人把两边改成
// 一致，这个用例会红，提醒把上面那段说明和断言一起更新。
fn test_attribute_less_method_is_known_divergence() {
	mut rr := new_route_registry()
	ctrl := &ScanConsistencyController{}
	rr.mount_controller[ScanConsistencyController, veb.Context](ctrl, '/scan')

	mut in_scan := false
	for r in scan_controller[ScanConsistencyController]() {
		if r.path == '/scan/convention_only' {
			in_scan = true
		}
	}
	mut in_registry := false
	for def in rr.routes {
		if def.path == '/scan/convention_only' {
			in_registry = true
		}
	}

	assert in_scan, 'scan_controller 不再把无属性方法当路由了？请同步更新本用例说明'
	assert !in_registry, 'mount_controller 开始注册无属性方法了？两边已经一致，请改成相等断言'
}

fn test_scan_controller_covers_tuple_style() {
	routes := scan_controller[ScanConsistencyController]()
	mut found := false
	for r in routes {
		if r.method == 'PUT' && r.path == '/scan/items/:id' {
			found = true
		}
	}
	assert found, '元组式 @[/items/:id; put] 没被扫出来，实际: ${scan_signature(routes)}'
}

fn test_scan_controller_applies_prefix() {
	routes := scan_controller[ScanConsistencyController]()
	for r in routes {
		assert r.path.starts_with('/scan'), '前缀没拼上: ${r.path}'
	}
}

// 无路由属性、只返回 veb.Result 的方法**也是**路由：veb 会给它 GET /方法名。
//
// 这条我一开始搞反了。当时读 veb 源码，看到 generate_routes 里
// has_route_attributes 这道门，就断言无属性方法进不了路由表，还写了「实测 404」
// 当证据 —— 但那次探针本身不合法（App 里嵌了 veb.Context）。
// 换成和 TestApp 一样的结构重测：/index、/ping 都返回 200。
//
// 这里的断言方向因此是「必须扫出来」：横幅少报一条真实可达的路由，
// 和人找不到入口一样坏。
fn test_scan_controller_includes_attribute_less_routes() {
	routes := scan_controller[ScanConsistencyController]()
	mut found := false
	for r in routes {
		if r.method == 'GET' && r.path == '/scan/convention_only' {
			found = true
		}
	}
	assert found, '无路由属性的 Result 方法没被扫出来，实际: ${scan_signature(routes)}'
}
