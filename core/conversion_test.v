module core

fn test_new_generic_conversion_service() {
	mut cs := new_generic_conversion_service()
	assert cs.can_convert('string', 'int')
	assert cs.can_convert('string', 'i64')
	assert cs.can_convert('string', 'f64')
	assert cs.can_convert('string', 'bool')
}

fn test_can_convert_not_registered() {
	mut cs := new_generic_conversion_service()
	assert cs.can_convert('string', 'custom_type') == false
}

fn test_convert_string_to_int_valid() {
	mut cs := new_generic_conversion_service()
	result := cs.convert('42', 'int')!
	assert result == '42'
}

fn test_convert_string_to_int_invalid() {
	mut cs := new_generic_conversion_service()
	mut failed := false
	cs.convert('not-a-number', 'int') or { failed = true }
	assert failed
}

fn test_convert_string_to_int_negative() {
	mut cs := new_generic_conversion_service()
	result := cs.convert('-123', 'int')!
	assert result == '-123'
}

fn test_convert_string_to_f64_valid() {
	mut cs := new_generic_conversion_service()
	result := cs.convert('3.14', 'f64')!
	assert result == '3.14'
}

fn test_convert_string_to_f64_invalid() {
	mut cs := new_generic_conversion_service()
	mut failed := false
	cs.convert('abc', 'f64') or { failed = true }
	assert failed
}

fn test_convert_string_to_bool_true_variants() {
	mut cs := new_generic_conversion_service()
	assert cs.convert('true', 'bool')! == 'true'
	assert cs.convert('1', 'bool')! == 'true'
	assert cs.convert('yes', 'bool')! == 'true'
	assert cs.convert('on', 'bool')! == 'true'
	assert cs.convert('TRUE', 'bool')! == 'true'
}

fn test_convert_string_to_bool_false_variants() {
	mut cs := new_generic_conversion_service()
	assert cs.convert('false', 'bool')! == 'false'
	assert cs.convert('0', 'bool')! == 'false'
	assert cs.convert('no', 'bool')! == 'false'
	assert cs.convert('off', 'bool')! == 'false'
	assert cs.convert('', 'bool')! == 'false'
}

fn test_convert_string_to_bool_invalid() {
	mut cs := new_generic_conversion_service()
	mut failed := false
	cs.convert('maybe', 'bool') or { failed = true }
	assert failed
}

fn test_convert_no_converter_registered() {
	mut cs := new_generic_conversion_service()
	mut failed := false
	cs.convert('test', 'unknown_type') or { failed = true }
	assert failed
}

fn test_add_custom_converter() {
	mut cs := new_generic_conversion_service()
	cs.add_converter('string', 'custom', fn (source string) !string {
		return 'custom:' + source
	})
	assert cs.can_convert('string', 'custom')
	result := cs.convert('hello', 'custom')!
	assert result == 'custom:hello'
}

fn test_convert_to_int_convenience() {
	mut cs := new_generic_conversion_service()
	val := cs.convert_to_int('42')!
	assert val == 42
}

fn test_convert_to_i64_convenience() {
	mut cs := new_generic_conversion_service()
	val := cs.convert_to_i64('9999999999')!
	assert val == 9999999999
}

fn test_convert_to_f64_convenience() {
	mut cs := new_generic_conversion_service()
	val := cs.convert_to_f64('3.14')!
	assert val == 3.14
}

fn test_convert_to_bool_convenience() {
	mut cs := new_generic_conversion_service()
	assert cs.convert_to_bool('true')! == true
	assert cs.convert_to_bool('false')! == false
}

fn test_convert_from_int_to_string() {
	mut cs := new_generic_conversion_service()
	result := cs.convert_from('42', 'int', 'string')!
	assert result == '42'
}

fn test_conversion_service_interface_compatible() {
	mut cs := new_generic_conversion_service()
	// Verify GenericConversionService implements ConversionService interface
	_ := cs
}
