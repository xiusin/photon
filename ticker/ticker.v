module ticker

// ticker.v - Photon Ticker Module Entry
//
// A high-performance timer/ticker implementation inspired by Go's
// runtime timer system. Features:
//
//   - 4-ary min-heap for efficient timer management
//   - 64-bucket sharding to reduce lock contention
//   - Go-compatible API: Timer, Ticker, Sleep, After, AfterFunc, Tick
//   - Channel-based notification with buffered capacity-1 channels
//   - Periodic ticker support with automatic re-insertion
//   - Zero external dependencies
//
// Usage:
//   import photon.ticker
//
//   // One-shot timer
//   t := ticker.new_timer(1 * time.second)
//   <-t.c  // blocks until timer fires
//
//   // Periodic ticker
//   tk := ticker.new_ticker(500 * time.millisecond)
//   for {
//       <-tk.c
//       // do something every 500ms
//   }
//
//   // Convenience
//   ticker.sleep(100 * time.millisecond)
//   ch := ticker.after(2 * time.second)
