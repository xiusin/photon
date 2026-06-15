module web

// form.v - Form Builder (Symfony Forms inspired)

// FormFieldType defines the type of form field
pub enum FormFieldType {
	text
	email
	password
	number
	textarea
	select_
	checkbox
	file
	hidden
}

// FormField defines a single field in a form
pub struct FormField {
pub:
	name       string
	field_type FormFieldType
pub mut:
	label      string
	value      string
	rules      []string
	options    []string
	required   bool
}

// FormBuilder constructs forms with validation rules
pub struct FormBuilder {
pub mut:
	fields map[string]FormField
}

// form creates a new FormBuilder
pub fn form() &FormBuilder {
	return &FormBuilder{
		fields: map[string]FormField{}
	}
}

// add adds a field to the form
pub fn (mut f FormBuilder) add(name string, field_type FormFieldType) &FormBuilder {
	f.fields[name] = FormField{
		name: name
		field_type: field_type
	}
	return f
}

// add_label sets the label for a field
pub fn (mut f FormBuilder) add_label(name string, label_text string) &FormBuilder {
	mut field := f.fields[name] or { return f }
	field.label = label_text
	f.fields[name] = field
	return f
}

// add_rule adds a validation rule to a field
pub fn (mut f FormBuilder) add_rule(name string, rule string) &FormBuilder {
	mut field := f.fields[name] or { return f }
	field.rules << rule
	f.fields[name] = field
	return f
}

// add_rules adds multiple validation rules to a field
pub fn (mut f FormBuilder) add_rules(name string, rule_list []string) &FormBuilder {
	mut field := f.fields[name] or { return f }
	field.rules << rule_list
	f.fields[name] = field
	return f
}

// add_options sets select options for a field
pub fn (mut f FormBuilder) add_options(name string, opts []string) &FormBuilder {
	mut field := f.fields[name] or { return f }
	field.options = opts.clone()
	f.fields[name] = field
	return f
}

// set_required marks a field as required
pub fn (mut f FormBuilder) set_required(name string, req bool) &FormBuilder {
	mut field := f.fields[name] or { return f }
	field.required = req
	f.fields[name] = field
	return f
}

// get_fields returns the form fields
pub fn (f &FormBuilder) get_fields() map[string]FormField {
	return f.fields.clone()
}

// get_field returns a specific field
pub fn (f &FormBuilder) get_field(name string) FormField {
	return f.fields[name] or { FormField{name: name} }
}
