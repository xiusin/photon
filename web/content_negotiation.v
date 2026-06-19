module web

// content_negotiation.v - Spring ContentNegotiationManager equivalent
//
// Provides content type negotiation based on Accept header, URL parameters,
// or fixed values. Spring equivalent: org.springframework.web.accept.ContentNegotiationManager

// ContentNegotiationStrategy resolves the content type for a request.
// Spring equivalent: org.springframework.web.accept.ContentNegotiationStrategy
pub interface ContentNegotiationStrategy {
	resolve_content_type(accept_header string, params map[string]string) !string
}

// ── AcceptHeaderStrategy ──

// AcceptHeaderStrategy resolves content type from the Accept header.
pub struct AcceptHeaderStrategy {
pub:
	default_media_type string = 'application/json'
}

pub fn new_accept_header_strategy() AcceptHeaderStrategy {
	return AcceptHeaderStrategy{}
}

pub fn (s AcceptHeaderStrategy) resolve_content_type(accept_header string, params map[string]string) !string {
	if accept_header.len == 0 {
		return s.default_media_type
	}

	// Parse Accept header: "text/html,application/json;q=0.9,*/*;q=0.8"
	parts := accept_header.split(',')
	mut best_type := ''
	mut best_q := f64(0.0)

	for part in parts {
		p := part.trim_space()
		mut media_type := p
		mut q := f64(1.0)

		// Extract q value if present
		if p.contains(';q=') {
			segments := p.split(';q=')
			if segments.len >= 2 {
				media_type = segments[0].trim_space()
				q = segments[1].trim_space().f64()
			}
		} else if p.contains(';') {
			segments := p.split(';')
			media_type = segments[0].trim_space()
		}

		// Skip wildcards for now (prefer specific types)
		if media_type == '*/*' {
			if best_type == '' && q > 0 {
				best_type = s.default_media_type
				best_q = q
			}
			continue
		}

		if q > best_q {
			best_q = q
			best_type = media_type
		}
	}

	if best_type.len == 0 {
		return s.default_media_type
	}
	return best_type
}

// ── ParameterStrategy ──

// ParameterStrategy resolves content type from a URL parameter (e.g. ?format=xml).
pub struct ParameterStrategy {
pub:
	param_name string = 'format'
mut:
	media_types map[string]string
}

pub fn new_parameter_strategy() ParameterStrategy {
	return ParameterStrategy{
		media_types: {
			'json': 'application/json'
			'xml':  'application/xml'
			'html': 'text/html'
			'text': 'text/plain'
		}
	}
}

pub fn (mut s ParameterStrategy) add_media_type(param_value string, media_type string) {
	s.media_types[param_value] = media_type
}

pub fn (s ParameterStrategy) resolve_content_type(accept_header string, params map[string]string) !string {
	param_name := s.param_name
	param_value := params[param_name] or { return error('parameter "${param_name}" not found') }
	return s.media_types[param_value] or {
		return error('no media type mapped for parameter value "${param_value}"')
	}
}

// ── FixedStrategy ──

// FixedStrategy always returns a fixed content type.
pub struct FixedStrategy {
pub:
	media_type string
}

pub fn new_fixed_strategy(media_type string) FixedStrategy {
	return FixedStrategy{
		media_type: media_type
	}
}

pub fn (s FixedStrategy) resolve_content_type(accept_header string, params map[string]string) !string {
	return s.media_type
}

// ── ContentNegotiationManager ──

// ContentNegotiationManager tries strategies in order until one succeeds.
pub struct ContentNegotiationManager {
pub mut:
	strategies []ContentNegotiationStrategy
}

pub fn new_content_negotiation_manager() ContentNegotiationManager {
	return ContentNegotiationManager{
		strategies: []ContentNegotiationStrategy{}
	}
}

pub fn (mut m ContentNegotiationManager) add_strategy(strategy ContentNegotiationStrategy) {
	m.strategies << strategy
}

pub fn (m ContentNegotiationManager) resolve_content_type(accept_header string, params map[string]string) !string {
	for strategy in m.strategies {
		result := strategy.resolve_content_type(accept_header, params) or { continue }
		return result
	}
	return error('no strategy could resolve content type')
}
