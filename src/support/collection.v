module support

// collection.v - Collection (Laravel Collection inspired)

// Collection wraps a slice with chainable methods
pub struct Collection[T] {
pub mut:
	items []T
}

// collect creates a new Collection from a slice
pub fn collect[T](items []T) Collection[T] {
	return Collection[T]{
		items: items.clone()
	}
}

// new_collection creates an empty Collection
pub fn new_collection[T]() Collection[T] {
	return Collection[T]{}
}

// all returns all items
pub fn (c &Collection[T]) all() []T {
	return c.items.clone()
}

// count returns the number of items
pub fn (c &Collection[T]) count() int {
	return c.items.len
}

// is_empty checks if the collection is empty
pub fn (c &Collection[T]) is_empty() bool {
	return c.items.len == 0
}

// is_not_empty checks if the collection has items
pub fn (c &Collection[T]) is_not_empty() bool {
	return c.items.len > 0
}

// ============================================================
// Transformation
// ============================================================

// map applies a function to each item and returns a new Collection
pub fn (c &Collection[T]) map[R](f fn (T) R) Collection[R] {
	mut result := []R{cap: c.items.len}
	for item in c.items {
		result << f(item)
	}
	return Collection[R]{
		items: result
	}
}

// filter returns items matching a predicate
pub fn (c &Collection[T]) filter(f fn (T) bool) Collection[T] {
	mut result := []T{}
	for item in c.items {
		if f(item) {
			result << item
		}
	}
	return Collection[T]{
		items: result
	}
}

// reject returns items NOT matching a predicate
pub fn (c &Collection[T]) reject(f fn (T) bool) Collection[T] {
	mut result := []T{}
	for item in c.items {
		if !f(item) {
			result << item
		}
	}
	return Collection[T]{
		items: result
	}
}

// each executes f for each item without mutation
pub fn (c &Collection[T]) each(f fn (T)) {
	for item in c.items {
		f(item)
	}
}

// reduce folds the collection to a single value
pub fn (c &Collection[T]) reduce[R](initial R, f fn (R, T) R) R {
	mut result := initial
	for item in c.items {
		result = f(result, item)
	}
	return result
}

// transform mutates items in-place and returns self
pub fn (mut c Collection[T]) transform(f fn (T) T) &Collection[T] {
	mut i := 0
	for i < c.items.len {
		c.items[i] = f(c.items[i])
		i++
	}
	return c
}

// ============================================================
// Accessors
// ============================================================

// first returns the first item or default
pub fn (c &Collection[T]) first(default_val T) T {
	if c.items.len > 0 {
		return c.items[0]
	}
	return default_val
}

// last returns the last item or default
pub fn (c &Collection[T]) last(default_val T) T {
	if c.items.len > 0 {
		return c.items[c.items.len - 1]
	}
	return default_val
}

// get returns the item at index or default
pub fn (c &Collection[T]) get(idx int, default_val T) T {
	if idx >= 0 && idx < c.items.len {
		return c.items[idx]
	}
	return default_val
}

// contains checks if an item exists in the collection
pub fn (c &Collection[T]) contains(f fn (T) bool) bool {
	for item in c.items {
		if f(item) {
			return true
		}
	}
	return false
}

// every checks if all items match a predicate
pub fn (c &Collection[T]) every(f fn (T) bool) bool {
	for item in c.items {
		if !f(item) {
			return false
		}
	}
	return true
}

// some checks if any item matches a predicate
pub fn (c &Collection[T]) some(f fn (T) bool) bool {
	for item in c.items {
		if f(item) {
			return true
		}
	}
	return false
}

// ============================================================
// Slicing & Chunking
// ============================================================

// chunk splits into chunks of the given size
pub fn (c &Collection[T]) chunk(size int) [][]T {
	return chunk(c.items, size)
}

// take returns the first n items
pub fn (c &Collection[T]) take(n int) Collection[T] {
	return Collection[T]{
		items: take(c.items, n)
	}
}

// skip returns items after skipping n
pub fn (c &Collection[T]) skip(n int) Collection[T] {
	return Collection[T]{
		items: skip(c.items, n)
	}
}

// slice returns items from start to end
pub fn (c &Collection[T]) slice(start int, end int) Collection[T] {
	mut e := end
	if e > c.items.len {
		e = c.items.len
	}
	if start < 0 || start >= e {
		return new_collection[T]()
	}
	return Collection[T]{
		items: c.items[start..e]
	}
}

// ============================================================
// Ordering
// ============================================================

// sort_by sorts the collection using a key extractor (ascending).
// Uses Schwartzian transform: extract keys once, sort indices, reorder.
// Complexity: O(n log n) via quicksort, with O(n) key extraction.
pub fn (c &Collection[T]) sort_by[R](f fn (T) R) Collection[T] {
	if c.items.len <= 1 {
		return Collection[T]{
			items: c.items.clone()
		}
	}

	n := c.items.len

	// Step 1: Extract keys once (Schwartzian transform)
	mut keys := []R{cap: n}
	mut indices := []int{cap: n}
	for i in 0 .. n {
		keys << f(c.items[i])
		indices << i
	}

	// Step 2: Quicksort indices by their corresponding keys
	quicksort_indices[R](mut keys, mut indices, 0, n - 1)

	// Step 3: Reorder items by sorted indices
	mut result := []T{cap: n}
	for idx in indices {
		result << c.items[idx]
	}

	return Collection[T]{
		items: result
	}
}

// quicksort_indices sorts indices in-place using keys (ascending)
fn quicksort_indices[R](mut keys []R, mut indices []int, lo int, hi int) {
	if lo >= hi {
		return
	}

	// Median-of-three pivot selection
	mid := lo + (hi - lo) / 2
	if keys[indices[lo]] > keys[indices[mid]] {
		indices[lo], indices[mid] = indices[mid], indices[lo]
	}
	if keys[indices[lo]] > keys[indices[hi]] {
		indices[lo], indices[hi] = indices[hi], indices[lo]
	}
	if keys[indices[mid]] > keys[indices[hi]] {
		indices[mid], indices[hi] = indices[hi], indices[mid]
	}
	pivot_val := keys[indices[mid]]

	// Hoare partition
	mut i := lo
	mut j := hi
	for {
		for keys[indices[i]] < pivot_val {
			i++
		}
		for keys[indices[j]] > pivot_val {
			j--
		}
		if i >= j { break
		 }
		indices[i], indices[j] = indices[j], indices[i]
		i++
		j--
	}

	quicksort_indices[R](mut keys, mut indices, lo, j)
	quicksort_indices[R](mut keys, mut indices, j + 1, hi)
}

// reverse reverses the order
pub fn (c &Collection[T]) reverse() Collection[T] {
	return Collection[T]{
		items: reverse(c.items)
	}
}

// ============================================================
// Grouping
// ============================================================

// group_by groups items by a key returned by f
pub fn (c &Collection[T]) group_by[K](f fn (T) K) map[K][]T {
	mut result := map[K][]T{}
	for item in c.items {
		key := f(item)
		result[key] << item
	}
	return result
}

// key_by keys items by a key returned by f (last wins for duplicates)
pub fn (c &Collection[T]) key_by[K](f fn (T) K) map[K]T {
	mut result := map[K]T{}
	for item in c.items {
		result[f(item)] = item
	}
	return result
}

// ============================================================
// Combination
// ============================================================

// merge combines two collections
pub fn (c &Collection[T]) merge(other Collection[T]) Collection[T] {
	mut result := c.items.clone()
	result << other.items
	return Collection[T]{
		items: result
	}
}

// concat appends items
pub fn (c &Collection[T]) concat(items []T) Collection[T] {
	mut result := c.items.clone()
	result << items
	return Collection[T]{
		items: result
	}
}

// push adds an item to the end
pub fn (mut c Collection[T]) push(item T) {
	c.items << item
}

// pop removes and returns the last item
pub fn (mut c Collection[T]) pop() T {
	last := c.items[c.items.len - 1]
	c.items.delete(c.items.len - 1)
	return last
}

// ============================================================
// Utility
// ============================================================

// tap executes a callback on the collection and returns it
pub fn (c &Collection[T]) tap[R](f fn (&Collection[T]) R) &Collection[T] {
	_ = f(c)
	return unsafe { c }
}

// pipe passes the collection through a callback
pub fn (c &Collection[T]) pipe[R](f fn (col Collection[T]) R) R {
	return f(Collection[T]{ items: c.items.clone() })
}

// ============================================================
// Conversion
// ============================================================

// to_vec returns the raw items slice
pub fn (c &Collection[T]) to_vec() []T {
	return c.items.clone()
}

// to_json serializes to JSON (simple implementation)
pub fn (c &Collection[T]) to_json() string {
	if c.items.len == 0 {
		return '[]'
	}
	mut parts := []string{cap: c.items.len}
	for item in c.items {
		parts << '${item}'
	}
	return '[' + parts.join(',') + ']'
}

// join joins items with a separator
pub fn (c &Collection[T]) join(sep string) string {
	mut result := ''
	for i, item in c.items {
		if i > 0 {
			result += sep
		}
		result += '${item}'
	}
	return result
}
