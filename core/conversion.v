module core

// conversion.v - Spring ConversionService equivalent
//
// Provides type conversion abstraction with pluggable converters.
// Spring equivalent: org.springframework.core.convert.ConversionService

// Converter converts source type S to target type T.
// Spring equivalent: org.springframework.core.convert.converter.Converter
pub interface Converter {
	convert(source string) !string
}

// ConversionService is the central type conversion service.
// Spring equivalent: org.springframework.core.convert.ConversionService
pub interface ConversionService {
	can_convert(source_type string, target_type string) bool
	convert(source string, target_type string) !string
}

// ConverterFn is a function-based converter (string → string).
pub type ConverterFn = fn (source string) !string

// GenericConversionService is the default ConversionService implementation.
// Stores converters keyed by "source_type->target_type".
pub struct GenericConversionService {
mut:
	converters map[string]ConverterFn
}

pub fn new_generic_conversion_service() GenericConversionService {
	mut cs := GenericConversionService{
		converters: map[string]ConverterFn{}
	}
	cs.register_builtin_converters()
	return cs
}

// converter_key builds the map key for a source→target conversion.
fn converter_key(source_type string, target_type string) string {
	return source_type + '->' + target_type
}

// add_converter registers a converter function for source_type→target_type.
pub fn (mut cs GenericConversionService) add_converter(source_type string, target_type string, converter ConverterFn) {
	cs.converters[converter_key(source_type, target_type)] = converter
}

// can_convert checks if a converter is registered for the given types.
pub fn (mut cs GenericConversionService) can_convert(source_type string, target_type string) bool {
	return converter_key(source_type, target_type) in cs.converters
}

// convert converts source string to target_type string representation.
pub fn (mut cs GenericConversionService) convert(source string, target_type string) !string {
	return cs.convert_from(source, 'string', target_type)
}

// convert_from converts source from source_type to target_type.
pub fn (mut cs GenericConversionService) convert_from(source string, source_type string, target_type string) !string {
	key := converter_key(source_type, target_type)
	converter := cs.converters[key] or {
		return error('no converter registered for ${source_type}->${target_type}')
	}
	return converter(source)!
}

// register_builtin_converters registers String→int/i64/f64/bool converters.
fn (mut cs GenericConversionService) register_builtin_converters() {
	// String → int
	cs.add_converter('string', 'int', fn (source string) !string {
		if !is_numeric_int(source) {
			return error('cannot convert "${source}" to int')
		}
		return source
	})

	// String → i64
	cs.add_converter('string', 'i64', fn (source string) !string {
		if !is_numeric_int(source) {
			return error('cannot convert "${source}" to i64')
		}
		return source
	})

	// String → f64
	cs.add_converter('string', 'f64', fn (source string) !string {
		if !is_numeric_float(source) {
			return error('cannot convert "${source}" to f64')
		}
		return source
	})

	// String → bool
	cs.add_converter('string', 'bool', fn (source string) !string {
		lower := source.to_lower()
		if lower == 'true' || lower == '1' || lower == 'yes' || lower == 'on' {
			return 'true'
		}
		if lower == 'false' || lower == '0' || lower == 'no' || lower == 'off' || lower == '' {
			return 'false'
		}
		return error('cannot convert "${source}" to bool')
	})

	// int → String
	cs.add_converter('int', 'string', fn (source string) !string {
		return source
	})

	// bool → String
	cs.add_converter('bool', 'string', fn (source string) !string {
		return source
	})
}

// is_numeric_int checks if string is a valid integer.
fn is_numeric_int(s string) bool {
	if s.len == 0 {
		return false
	}
	mut start := 0
	if s[0] == `-` || s[0] == `+` {
		if s.len == 1 {
			return false
		}
		start = 1
	}
	for i in start .. s.len {
		if s[i] < `0` || s[i] > `9` {
			return false
		}
	}
	return true
}

// is_numeric_float checks if string is a valid float.
fn is_numeric_float(s string) bool {
	if s.len == 0 {
		return false
	}
	mut start := 0
	if s[0] == `-` || s[0] == `+` {
		if s.len == 1 {
			return false
		}
		start = 1
	}
	mut has_digit := false
	mut has_dot := false
	for i in start .. s.len {
		if s[i] == `.` {
			if has_dot {
				return false
			}
			has_dot = true
		} else if s[i] < `0` || s[i] > `9` {
			return false
		} else {
			has_digit = true
		}
	}
	return has_digit
}

// Convenience methods for common conversions
pub fn (mut cs GenericConversionService) convert_to_int(source string) !int {
	result := cs.convert(source, 'int')!
	return result.int()
}

pub fn (mut cs GenericConversionService) convert_to_i64(source string) !i64 {
	result := cs.convert(source, 'i64')!
	return result.i64()
}

pub fn (mut cs GenericConversionService) convert_to_f64(source string) !f64 {
	result := cs.convert(source, 'f64')!
	return result.f64()
}

pub fn (mut cs GenericConversionService) convert_to_bool(source string) !bool {
	result := cs.convert(source, 'bool')!
	return result == 'true'
}
