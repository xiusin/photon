module async

// async.v - Photon Async Module Entry
//
// A thread-pool-based asynchronous task execution module, inspired by
// Spring's @Async / TaskExecutor abstraction.
//
// Features:
//
//   - Bounded thread pool with configurable worker count and queue size
//   - Blocking submit() with backpressure for overload protection
//   - Non-blocking try_submit() for droppable tasks
//   - Graceful shutdown that drains all in-flight tasks
//   - @[async] annotation discovery via comptime scanning (zero runtime reflection)
//   - wait_all() barrier for batch synchronization
//
// Usage:
//
//   import photon.async
//
//   // 1. Create an executor
//   mut te := async.new_task_executor(4, 64)
//   defer { te.shutdown() }
//
//   // 2. Submit tasks
//   te.submit(fn () {
//       send_email(user)
//   })!
//
//   // 3. Wait for completion
//   te.wait_all()
//
//   // 4. Annotation discovery (comptime)
//   methods := async.extract_async_methods[EmailService]()
//   // methods contains all @[async] methods on EmailService
