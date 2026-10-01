// Identifier and anchor rules for the JSON Schema specifications
// (Python's `referencing.jsonschema` private helpers).

///|
fn string_member(contents : Json, key : String) -> String? {
  match contents {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// `$id` (draft 2019-09 and later): booleans have no ID.
///
/// Python's `_dollar_id`.
pub fn dollar_id(contents : Json) -> String? {
  string_member(contents, "$id")
}

///|
/// `$id` in drafts 6 and 7: ignored next to `$ref` (whose siblings are
/// ignored in those drafts), and plain-name fragments (`#foo`) are anchors,
/// not IDs.
///
/// Python's `_legacy_dollar_id`.
pub fn legacy_dollar_id(contents : Json) -> String? {
  guard contents is Object(obj) && !obj.contains("$ref") else { return None }
  match string_member(contents, "$id") {
    Some(id) if !id.has_prefix("#") => Some(id)
    _ => None
  }
}

///|
/// `id` in drafts 3 and 4: ignored next to `$ref`, and plain-name fragments
/// (`#foo`) are anchors, not IDs.
///
/// Python's `_legacy_id`.
pub fn legacy_id(contents : Json) -> String? {
  guard contents is Object(obj) && !obj.contains("$ref") else { return None }
  match string_member(contents, "id") {
    Some(id) if !id.has_prefix("#") => Some(id)
    _ => None
  }
}

///|
/// `$anchor` and `$dynamicAnchor` (draft 2020-12).
///
/// Python's `_anchor`.
pub fn anchors_2020(
  specification : Specification,
  contents : Json,
) -> Array[Anchor] {
  let anchors = []
  if string_member(contents, "$anchor") is Some(name) {
    anchors.push(
      Anchor::new(name~, resource=specification.create_resource(contents)),
    )
  }
  if string_member(contents, "$dynamicAnchor") is Some(name) {
    anchors.push(
      dynamic_anchor(name~, resource=specification.create_resource(contents)),
    )
  }
  anchors
}

///|
/// `$anchor` (draft 2019-09).
///
/// Python's `_anchor_2019`.
pub fn anchors_2019(
  specification : Specification,
  contents : Json,
) -> Array[Anchor] {
  match string_member(contents, "$anchor") {
    Some(name) =>
      [Anchor::new(name~, resource=specification.create_resource(contents))]
    None => []
  }
}

///|
fn legacy_anchor_in(
  key : String,
  specification : Specification,
  contents : Json,
) -> Array[Anchor] {
  match string_member(contents, key) {
    Some(id) if id.has_prefix("#") =>
      [
        Anchor::new(
          name=id.view(start_offset=1).to_owned(),
          resource=specification.create_resource(contents),
        ),
      ]
    _ => []
  }
}

///|
/// Plain-name fragments in `$id` (`{"$id": "#foo"}`), drafts 6 and 7.
///
/// Python's `_legacy_anchor_in_dollar_id`.
pub fn legacy_anchor_in_dollar_id(
  specification : Specification,
  contents : Json,
) -> Array[Anchor] {
  legacy_anchor_in("$id", specification, contents)
}

///|
/// Plain-name fragments in `id` (`{"id": "#foo"}`), drafts 3 and 4.
///
/// Python's `_legacy_anchor_in_id`.
pub fn legacy_anchor_in_id(
  specification : Specification,
  contents : Json,
) -> Array[Anchor] {
  legacy_anchor_in("id", specification, contents)
}
