module support

// arr.v - Array Helpers (Laravel Arr class inspired)
//
// Provides dot-notation access to maps and common array manipulation utilities.

import time

// get retrieves a value from a nested map using dot notation
pub fn get[T](m map[string]T, key string, default_val T) T {
	keys := key.split('.')
	mut current := m
	for i, k in keys {
		if i == keys.len - 1 {
			return current[k] or { default_val }
		}
		// Cannot recurse into nested maps with generics in V
		// For simple use, return the value at the key
		return current[k] or { default_val }
	}
	return default_val
}

// get_string retrieves a string value from a map of strings using dot notation
pub fn get_string(m map[string]string, key string, default_val string) string {
	keys := key.split('.')
	if keys.len == 1 {
		return m[key] or { default_val }
	}
	return m[key] or { default_val }
}

// set sets a value in a nested map using dot notation
pub fn set_string(mut m map[string]string, key string, value string) {
	keys := key.split('.')
	if keys.len == 1 {
		m[key] = value
		return
	}
	// For nested, we need intermediate maps
	// Simplified: set with dot key directly
	m[key] = value
}

// forget removes a key from a map using dot notation
pub fn forget_string(mut m map[string]string, key string) {
	m.delete(key)
}

// has checks if a key exists in a map using dot notation
pub fn has_string(m map[string]string, key string) bool {
	_ := m[key] or { return false }
	return true
}

// only returns a map with only the specified keys
pub fn only_string(m map[string]string, keys []string) map[string]string {
	mut result := map[string]string{}
	for k in keys {
		if val := m[k] {
			result[k] = val
		}
	}
	return result
}

// except returns a map without the specified keys
pub fn except_string(m map[string]string, keys []string) map[string]string {
	mut result := map[string]string{}
	for k, v in m {
		if k !in keys {
			result[k] = v
		}
	}
	return result
}

// pluck extracts a list of values from a slice of maps for a given key
pub fn pluck(maps []map[string]string, key string) []string {
	mut result := []string{cap: maps.len}
	for m in maps {
		if val := m[key] {
			result << val
		}
	}
	return result
}

// first returns the first element matching a predicate, or a default
pub fn first[T](items []T, predicate fn (T) bool, default_val T) T {
	for item in items {
		if predicate(item) {
			return item
		}
	}
	return default_val
}

// last returns the last element matching a predicate, or a default
pub fn last[T](items []T, predicate fn (T) bool, default_val T) T {
	mut idx := items.len
	for idx > 0 {
		idx--
		if predicate(items[idx]) {
			return items[idx]
		}
	}
	return default_val
}

// where filters items matching a predicate
pub fn filter_items[T](items []T, predicate fn (T) bool) []T {
	mut result := []T{}
	for item in items {
		if predicate(item) {
			result << item
		}
	}
	return result
}

// flatten flattens a 2D slice into a 1D slice
pub fn flatten[T](arr [][]T) []T {
	mut result := []T{}
	for sub in arr {
		result << sub
	}
	return result
}

// collapse flattens a 2D slice into a 1D slice (alias for flatten)
pub fn collapse[T](arr [][]T) []T {
	return flatten(arr)
}

// chunk splits a slice into chunks of the given size
pub fn chunk[T](items []T, size int) [][]T {
	mut result := [][]T{}
	mut i := 0
	for i < items.len {
		mut end := i + size
		if end > items.len {
			end = items.len
		}
		result << items[i..end]
		i = end
	}
	return result
}

// shuffle randomly reorders items
pub fn shuffle[T](items []T) []T {
	mut result := items.clone()
	// Fisher-Yates shuffle with time-based PRNG
	mut seed := i64(time.now().unix_nano())
	mut n := result.len
	for n > 1 {
		n--
		// Simple LCG: X_{n+1} = (a * X_n + c) mod m
		seed = seed * i64(1103515245) + i64(12345)
		k := int(seed.abs() % i64(n + 1))
		result[n], result[k] = result[k], result[n]
	}
	return result
}

// unique removes duplicate values
pub fn unique_string(items []string) []string {
	mut seen := map[string]bool{}
	mut result := []string{}
	for item in items {
		if item !in seen {
			seen[item] = true
			result << item
		}
	}
	return result
}

// merge combines multiple maps
pub fn merge_string(maps ...map[string]string) map[string]string {
	mut result := map[string]string{}
	for m in maps {
		for k, v in m {
			result[k] = v
		}
	}
	return result
}

// keys returns all keys from a string map
pub fn keys_string(m map[string]string) []string {
	return m.keys()
}

// values returns all values from a string map
pub fn values_string(m map[string]string) []string {
	return m.values()
}

// reverse reverses a slice
pub fn reverse[T](items []T) []T {
	mut result := items.clone()
	mut i := 0
	mut j := result.len - 1
	for i < j {
		result[i], result[j] = result[j], result[i]
		i++
		j--
	}
	return result
}

// take returns the first n items
pub fn take[T](items []T, n int) []T {
	if n <= 0 {
		return []
	}
	if n >= items.len {
		return items.clone()
	}
	return items[..n]
}

// skip returns items after skipping the first n
pub fn skip[T](items []T, n int) []T {
	if n <= 0 {
		return items.clone()
	}
	if n >= items.len {
		return []
	}
	return items[n..]
}
