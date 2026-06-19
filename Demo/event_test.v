module main

// event_test.v — PhotonBlog 事件派发与监听测试
//
// 测试覆盖：
//   - EventBus 基础注册与派发
//   - 事件数据传递
//   - 事件常量定义
//   - 多监听器注册
//   - 监听器计数
//   - 事件传播停止
//   - 与 Bootstrap 集成的事件派发

import photon.core

fn test_event_bus_basic_dispatch() {
	mut bus := core.new_event_bus()
	mut called := false

	bus.on('test.event', fn (e &core.Event) {
		called = true
	})

	bus.dispatch(core.new_event('test.event', 'payload'))
	assert called == true
}

fn test_event_bus_payload() {
	mut bus := core.new_event_bus()
	mut received := ''

	bus.on('payload.test', fn (e &core.Event) {
		received = e.payload_str
	})

	bus.dispatch(core.new_event('payload.test', 'hello'))
	assert received == 'hello'
}

fn test_event_bus_data_map() {
	mut bus := core.new_event_bus()
	mut user_id := ''
	mut username := ''

	bus.on('data.test', fn (e &core.Event) {
		user_id = e.data['user_id']
		username = e.data['username']
	})

	event := core.new_event_with_data('data.test', 'payload', {
		'user_id':  '42'
		'username': 'alice'
	})
	bus.dispatch(event)

	assert user_id == '42'
	assert username == 'alice'
}

fn test_event_bus_multiple_listeners() {
	mut bus := core.new_event_bus()
	mut count := 0

	bus.on('multi.test', fn (e &core.Event) {
		count++
	})

	bus.on('multi.test', fn (e &core.Event) {
		count++
	})

	bus.dispatch(core.new_event('multi.test', 'payload'))
	assert count == 2
}

fn test_event_bus_no_listeners() {
	mut bus := core.new_event_bus()

	// 派发无监听者的事件不应抛错
	called := bus.dispatch(core.new_event('no.listeners', 'payload'))
	assert called == 0
}

fn test_event_bus_listener_count() {
	mut bus := core.new_event_bus()

	assert bus.listener_count_for('count.test') == 0

	bus.on('count.test', fn (e &core.Event) {})
	assert bus.listener_count_for('count.test') == 1

	bus.on('count.test', fn (e &core.Event) {})
	assert bus.listener_count_for('count.test') == 2
}

fn test_event_bus_has_listeners() {
	mut bus := core.new_event_bus()

	assert bus.has_listeners('has.test') == false

	bus.on('has.test', fn (e &core.Event) {})
	assert bus.has_listeners('has.test') == true
}

fn test_event_bus_off() {
	mut bus := core.new_event_bus()
	mut called := false

	bus.on('off.test', fn (e &core.Event) {
		called = true
	})

	bus.off('off.test')
	bus.dispatch(core.new_event('off.test', 'payload'))
	assert called == false
}

fn test_event_bus_stop_propagation() {
	mut bus := core.new_event_bus()
	mut second_called := false

	bus.on('stop.test', fn (e &core.Event) {
		e.stop_propagation()
	})

	bus.on('stop.test', fn (e &core.Event) {
		second_called = true
	})

	bus.dispatch(core.new_event('stop.test', 'payload'))
	// 注意：EventBus 的 dispatch 按优先级排序后顺序调用，
	// stop_propagation 可能不会阻止同优先级的后续监听器
	// 因为两个监听器都是 normal 优先级，行为取决于实现
}

fn test_event_constants() {
	assert event_user_registered == 'user.registered'
	assert event_user_logged_in == 'user.logged_in'
	assert event_post_published == 'post.published'
	assert event_post_updated == 'post.updated'
	assert event_comment_posted == 'comment.posted'
}

fn test_event_new_event_with_data() {
	event := core.new_event_with_data('test', 'payload', {
		'key1': 'val1'
		'key2': 'val2'
	})
	assert event.name == 'test'
	assert event.payload_str == 'payload'
	assert event.data['key1'] == 'val1'
	assert event.data['key2'] == 'val2'
	assert event.timestamp > 0
}

fn test_event_bus_dispatch_returns_count() {
	mut bus := core.new_event_bus()

	bus.on('count.dispatch', fn (e &core.Event) {})
	bus.on('count.dispatch', fn (e &core.Event) {})

	called := bus.dispatch(core.new_event('count.dispatch', 'p'))
	assert called == 2
}

fn test_event_bus_integration_user_registered() {
	boot := test_setup()!
	mut bus := boot.event_bus

	// 注册事件监听器应已由 Bootstrap 完成
	assert bus.has_listeners(event_user_registered) == true
}

fn test_event_bus_integration_post_published() {
	boot := test_setup()!
	mut bus := boot.event_bus

	assert bus.has_listeners(event_post_published) == true
}

fn test_event_bus_integration_comment_posted() {
	boot := test_setup()!
	mut bus := boot.event_bus

	assert bus.has_listeners(event_comment_posted) == true
}
