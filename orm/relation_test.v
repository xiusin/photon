module orm

// relation_test.v - Tests for Relationship, HasMany, BelongsTo, ManyToMany, HasOne, RelationLoader

// --- Relationship Tests ---

fn test_relationship_has_many() {
	rel := Relationship{
		name: 'posts'
		typ: 'has_many'
		target: 'Post'
		foreign_key: 'user_id'
		local_key: 'id'
	}
	assert rel.name == 'posts'
	assert rel.typ == 'has_many'
	assert rel.target == 'Post'
	assert rel.foreign_key == 'user_id'
	assert rel.local_key == 'id'
	assert rel.pivot_table == ''
}

fn test_relationship_belongs_to() {
	rel := Relationship{
		name: 'author'
		typ: 'belongs_to'
		target: 'User'
		foreign_key: 'author_id'
		local_key: 'id'
	}
	assert rel.name == 'author'
	assert rel.typ == 'belongs_to'
	assert rel.target == 'User'
}

fn test_relationship_many_to_many() {
	rel := Relationship{
		name: 'tags'
		typ: 'many_to_many'
		target: 'Tag'
		foreign_key: 'tag_id'
		local_key: 'post_id'
		pivot_table: 'post_tags'
	}
	assert rel.name == 'tags'
	assert rel.typ == 'many_to_many'
	assert rel.target == 'Tag'
	assert rel.pivot_table == 'post_tags'
}

fn test_relationship_has_one() {
	rel := Relationship{
		name: 'profile'
		typ: 'has_one'
		target: 'Profile'
		foreign_key: 'user_id'
		local_key: 'id'
	}
	assert rel.name == 'profile'
	assert rel.typ == 'has_one'
	assert rel.target == 'Profile'
}

// --- HasMany Tests ---

struct Post {}
struct Tag {}

fn test_new_has_many() {
	hm := new_has_many[Post]()
	assert hm.loaded == false
}

fn test_new_has_many_struct() {
	hm := HasMany[Post]{}
	assert hm.loaded == false
}

// --- BelongsTo Tests ---

fn test_new_belongs_to() {
	bt := new_belongs_to[Post]()
	assert bt.loaded == false
}

fn test_new_belongs_to_struct() {
	bt := BelongsTo[Post]{}
	assert bt.loaded == false
}

// --- ManyToMany Tests ---

fn test_new_many_to_many() {
	mtm := new_many_to_many[Tag]()
	assert mtm.loaded == false
}

fn test_new_many_to_many_struct() {
	mtm := ManyToMany[Tag]{}
	assert mtm.loaded == false
}

// --- HasOne Tests ---

fn test_new_has_one() {
	ho := new_has_one[Post]()
	assert ho.loaded == false
}

fn test_new_has_one_struct() {
	ho := HasOne[Post]{}
	assert ho.loaded == false
}

// --- Integration: Combining relationships on a struct ---

struct User {
pub:
	id int
pub mut:
	posts HasMany[Post]
	profile HasOne[Post]
}

fn test_user_entity_with_relationships() {
	mut user := User{
		id: 1
		posts: new_has_many[Post]()
		profile: new_has_one[Post]()
	}
	assert user.id == 1
	assert user.posts.loaded == false
	assert user.profile.loaded == false
}

// --- RelationLoader Tests ---

fn test_new_relation_loader() {
	om := new_orm_manager()
	rl := new_relation_loader(om)
	assert true // no crash
	_ = rl
}

// --- Relationship combinations ---

fn test_relationship_all_types_differ() {
	// Each relationship type should be distinguishable
	has_many_rel := Relationship{ typ: 'has_many' }
	belongs_to_rel := Relationship{ typ: 'belongs_to' }
	many_to_many_rel := Relationship{ typ: 'many_to_many' }
	has_one_rel := Relationship{ typ: 'has_one' }

	assert has_many_rel.typ != belongs_to_rel.typ
	assert belongs_to_rel.typ != many_to_many_rel.typ
	assert many_to_many_rel.typ != has_one_rel.typ
	assert has_one_rel.typ != has_many_rel.typ
}
