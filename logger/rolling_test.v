module logger

// rolling_test.v - FileChannel 按大小轮转
//
// 之前 logger 完全没有轮转：一个长期运行的服务会把 app.log 写到磁盘满，
// 而 FileChannel 的注释里却写着「外部轮转后调 reopen()」—— 手册把责任
// 推给了用户，框架自己什么都不做。
//
// 这组用例锁住三件事：
//   1. max_size_bytes 之外的写入会切到新文件，旧文件按 .1 / .2 顺延
//   2. max_backups 之外的历史文件会被删除，磁盘占用有界
//   3. 进程重启后按文件实际大小继续计数，不会「以为文件是空的」
import os
import time

// tmp_log_path 生成一个测试用的临时日志路径。
fn tmp_log_path(name string) string {
	dir := os.join_path(os.temp_dir(), 'photon-rolling-${time.now().unix_nano()}')
	os.mkdir_all(dir) or {}
	return os.join_path(dir, name)
}

fn backup_of(path string, index int) string {
	return '${path}.${index}'
}

fn test_file_channel_writes_without_rotation_by_default() {
	path := tmp_log_path('plain.log')
	mut ch := new_file_channel(path)
	for i in 0 .. 50 {
		ch.write(.info, 'line ${i}', map[string]string{})
	}
	ch.close()

	assert os.exists(path)
	assert os.file_size(path) > 0
	assert !os.exists(backup_of(path, 1))
	assert ch.rotation_count() == 0
	os.rmdir_all(os.dir(path)) or {}
}

fn test_rotation_creates_backup_files() {
	path := tmp_log_path('roll.log')
	mut ch := new_rolling_file_channel(
		filepath: path
		max_size_bytes: 400
		max_backups: 3
	)
	// 每条日志行都带时间戳与级别，长度不小 —— 写 40 条必然多次轮转
	for i in 0 .. 40 {
		ch.write(.info, 'payload-${i}', map[string]string{})
	}
	ch.close()

	assert ch.rotation_count() > 0, 'size-based rotation never triggered'
	assert os.exists(backup_of(path, 1)), '.1 backup missing'
	// 当前文件必须小于上限（最后一条可能刚好越界，留一行余量）
	assert os.file_size(path) <= 400 + 200

	os.rmdir_all(os.dir(path)) or {}
}

fn test_rotation_keeps_only_max_backups() {
	path := tmp_log_path('bounded.log')
	max_backups := 2
	mut ch := new_rolling_file_channel(
		filepath: path
		max_size_bytes: 200
		max_backups: max_backups
	)
	for i in 0 .. 60 {
		ch.write(.info, 'payload-${i}', map[string]string{})
	}
	ch.close()

	// .1 与 .2 存在，.3 必须已被删除
	assert os.exists(backup_of(path, 1))
	assert os.exists(backup_of(path, 2))
	assert !os.exists(backup_of(path, 3)), 'backups beyond max_backups must be removed'

	os.rmdir_all(os.dir(path)) or {}
}

fn test_rotation_without_backups_truncates() {
	path := tmp_log_path('nobak.log')
	mut ch := new_rolling_file_channel(
		filepath: path
		max_size_bytes: 200
		max_backups: 0
	)
	for i in 0 .. 30 {
		ch.write(.info, 'payload-${i}', map[string]string{})
	}
	ch.close()

	assert ch.rotation_count() > 0
	assert !os.exists(backup_of(path, 1)), 'max_backups=0 must not keep history'
	assert os.exists(path)

	os.rmdir_all(os.dir(path)) or {}
}

fn test_counter_is_seeded_from_existing_file() {
	path := tmp_log_path('seeded.log')
	// 先写满一个大文件，再新建一个通道（模拟进程重启）
	os.write_file(path, 'x'.repeat(900)) or { assert false }
	mut ch := new_rolling_file_channel(
		filepath: path
		max_size_bytes: 400
		max_backups: 1
	)
	ch.write(.info, 'after-restart', map[string]string{})
	ch.close()

	assert ch.rotation_count() == 1, 'existing file size was ignored, written counter started at 0'
	assert os.exists(backup_of(path, 1))
	// 新文件里只有重启后那一条
	content := os.read_file(path) or { '' }
	assert content.contains('after-restart')

	os.rmdir_all(os.dir(path)) or {}
}

fn test_rotation_config_defaults() {
	cfg := FileChannelConfig{
		filepath: '/tmp/x.log'
	}
	assert cfg.max_size_bytes == 0
	assert cfg.max_backups == 3

	ch := new_rolling_file_channel(filepath: '/tmp/x.log')
	assert ch.max_size_bytes == 0
	assert ch.max_backups == 3
}

fn test_logger_add_sink_with_rolling_channel() {
	path := tmp_log_path('via-logger.log')
	mut log_ := new()
	log_.set_level(.debug)
	rot := new_rolling_file_channel(
		filepath: path
		max_size_bytes: 300
		max_backups: 2
	)
	log_.add_sink(rot)

	for i in 0 .. 30 {
		log_.info('message-${i}')
	}
	rot.close()

	assert os.exists(path)
	assert rot.rotation_count() > 0
	// max_backups: 2 —— .3 不该存在
	assert !os.exists(backup_of(path, 3))
	assert log_.sinks().len == 1

	os.rmdir_all(os.dir(path)) or {}
}
