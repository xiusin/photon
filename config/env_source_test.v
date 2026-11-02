module config

// env_source_test.v — 环境变量源必须真的读到环境变量。
//
// 回归：`EnvConfigSource.load()` 曾把 `os.environ()` 当字符串数组遍历
// （`for _, env_var in env_vars` 实际拿到的是 map 的**键**），
// `split_nth('=', 1)` 因此永远分不出两段，`load()` 恒返回空 map。
// 配了 `prefix: 'APP_'` 也读不到任何东西 —— 这个源形同虚设。

import os

fn test_env_source_reads_prefixed_vars() {
	os.setenv('PHOTON_CFG_DB_HOST', 'envhost', true)
	os.setenv('PHOTON_CFG_DB_PORT', '5433', true)
	mut s := new_env_config_source('PHOTON_CFG_')
	props := s.load()!
	// 前缀被剥掉，键统一小写，和属性文件里的写法对齐
	assert props['db_host'] == 'envhost'
	assert props['db_port'] == '5433'
	// 前缀没有原样留在键里
	assert 'photon_cfg_db_host' !in props
}

fn test_env_source_ignores_other_prefixes() {
	os.setenv('PHOTON_CFG_ONLY', 'kept', true)
	os.setenv('OTHER_PREFIX_ONLY', 'dropped', true)
	mut s := new_env_config_source('PHOTON_CFG_')
	props := s.load()!
	assert props['only'] == 'kept'
	mut leaked := false
	for key, _ in props {
		if key.contains('other_prefix') {
			leaked = true
		}
	}
	assert !leaked
}
