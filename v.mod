Module {
	name: 'photon'
	description: 'Photon Framework - A commercial-grade Spring-like application framework for V language'
	version: '0.1.0'
	license: 'MIT'
	repo_url: 'https://github.com/photon-framework/photon'
	// vendor/modules/xiusin/vredis 由本仓库维护（见 vendor/README.md）。
	// 名字沿用上游 xiusin.vredis，因此 `import xiusin.vredis` 无需改动；
	// 本地/CI 用 scripts/sync-vendor.sh 把它接进 V 的模块搜索路径。
	dependencies: [] // 无外部依赖：唯一第三方代码已 vendor 进仓库
}
