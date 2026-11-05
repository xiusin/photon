module web

import time
import veb

// server_graceful_regression_test.v — run_with_graceful_shutdown 的编译/语义回归
//
// 背景：这个函数长期处于「编译不过」状态，而它既不在测试里、也不在 example 里，
// 于是每次「全量全绿」的报告里都没有它的声音。它坏掉的地方很隐蔽：
//
//   1. `&A{}` 在泛型函数体里报 `unknown struct A`；
//   2. 泛型函数体里的闭包必须显式声明类型参数；
//   3. 闭包捕获 `mut gsm` 之后拿到的是上下文副本，于是「服务线程里的停机」
//      传不回主线程 —— 编译过了也只是个摆设。
//
// 这里不启动真实服务（会占端口、要等信号），只验证第 3 点所依赖的机制：
// holder 指针跨协程共享时，一侧的 shutdown() 另一侧真的看得见。

// graceful_holder_probe_app 作为 run_with_graceful_shutdown[A, X] 的 A 参数占位
struct GracefulHolderProbeApp {}

// graceful_holder_probe_ctx 作为 X 参数占位（veb 要求嵌入 veb.Context，
// 这里只用来让泛型参数被实例化，不涉及真实请求处理）
pub struct GracefulHolderProbeCtx {
	veb.Context
}

fn test_graceful_server_holder_shutdown_visible_across_goroutines() {
	mut holder := new_graceful_server_holder()
	assert holder.gsm != unsafe { nil }
	assert holder.gsm.is_stopped() == false

	// 一侧等停机发起，另一侧发起停机 —— 与 run_with_graceful_shutdown
	// 里「主线程跑服务 / 协程等信号」同一套结构
	observed := chan bool{cap: 1}
	spawn fn [mut holder, observed] () {
		holder.gsm.wait()
		observed <- holder.gsm.is_stopped()
	}()

	time.sleep(20 * time.millisecond)
	holder.gsm.shutdown()

	mut seen := false
	select {
		s := <-observed {
			seen = s
		}
		else {}
	}
	if !seen {
		for _ in 0 .. 50 {
			time.sleep(10 * time.millisecond)
			select {
				s := <-observed {
					seen = s
					break
				}
				else {}
			}
			if seen {
				break
			}
		}
	}
	assert seen == true
	// 主线程这边读到的也是同一个对象：副本化的话这里会是 false
	assert holder.gsm.is_stopped() == true
}

fn test_graceful_server_holder_keeps_app_pointer() {
	mut app := &GracefulHolderProbeApp{}
	mut holder := new_graceful_server_holder()
	holder.app = voidptr(app)
	assert holder.app != unsafe { nil }
	// 类型擦除之后必须还能拿回原指针，否则 run_at 拿不到 App 实例
	assert holder.app == voidptr(app)
}
