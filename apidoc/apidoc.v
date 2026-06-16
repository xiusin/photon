module apidoc

// apidoc.v — API 文档自动生成模块入口
//
// 通过非侵入式中间件自动采集 HTTP 请求/响应数据，
// 生成可编辑、可锁定的 API 接口文档。
//
// 使用方式（在 main.v 的 App 结构体中）：
//   pub struct App {
//       veb.Context
//   pub mut:
//       api_doc   &apidoc.Collector = unsafe { nil }
//       doc_store &apidoc.ApiDocStore = unsafe { nil }
//   }
//
//   // before_request:
//   app.api_doc.collect(mut ctx.Context)
//
//   // after_request:
//   app.api_doc.collect_response(mut ctx.Context)
//
// 内置路由（需用户在 controllers.v 中注册）：
//   GET  /__docs                   → 文档首页（静态 HTML）
//   GET  /__docs/static/*          → 静态资源（CSS/JS）
//   GET  /__docs/api/entries       → 获取所有条目 JSON
//   GET  /__docs/api/entries/:id   → 获取单条 JSON
//   PUT  /__docs/api/entries/:id   → 更新条目（编辑/锁定）
//   DELETE  /__docs/api/entries/:id → 删除条目

import json

// ============================================================
// 初始化入口（用户调用）
// ============================================================

// init 一键初始化 API 文档模块
// data_dir: 数据持久化目录（如 "./data/apidoc"）
// 返回 (*ApiDocStore, *Collector)
pub fn init(data_dir string) !(&ApiDocStore, &Collector) {
	store := new_store(data_dir)!
	coll := new_collector(store)
	return store, coll
}

// ============================================================
// 静态资源嵌入（编译时注入）
// ============================================================

// static_dir 返回静态资源目录路径
pub fn static_dir() string {
	return 'apidoc/static'
}

// ============================================================
// 响应序列化（用于 API 控制器）
// ============================================================

// api_error 构造错误响应
pub fn api_error(code int, msg string) string {
	return json.encode({
		'code':    '${code}'
		'message': msg
	})
}

// encode_response 手动构建响应 JSON（避免泛型问题）
pub fn encode_response(code int, msg string, data_str string) string {
	return '{"code":"${code}","message":"${msg}","data":${data_str}}'
}
