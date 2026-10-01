// Subresource discovery and pointer-traversal rules for the JSON Schema
// specifications (Python's `referencing.jsonschema` factories).

///|
/// Which "funky" keywords of older drafts a `subresources_of` handles in
/// addition to the plain keyword sets.
priv enum Quirks {
  /// draft 2020-12: none
  NoQuirks
  /// draft 2019-09: `items` may be an array
  CrazyItems
  /// drafts 6 and 7: also `dependencies`
  CrazyItemsDependencies
  /// drafts 3 and 4: also `additionalItems` / `additionalProperties` objects
  CrazyAPItemsDependencies
}

///|
fn make_subresources_of(
  in_value~ : Array[String],
  in_subvalues~ : Array[String],
  in_subarray~ : Array[String],
  quirks~ : Quirks,
) -> (Json) -> Array[Json] {
  contents => {
    guard contents is Object(obj) else { return [] }
    let out = []
    for each in in_value {
      if obj.get(each) is Some(value) {
        out.push(value)
      }
    }
    for each in in_subarray {
      if obj.get(each) is Some(Array(values)) {
        out.append(values)
      }
    }
    for each in in_subvalues {
      if obj.get(each) is Some(Object(values)) {
        for _, value in values {
          out.push(value)
        }
      }
    }
    if quirks is NoQuirks {
      return out
    }
    match obj.get("items") {
      Some(Array(items)) => out.append(items)
      Some(items) => out.push(items)
      None => ()
    }
    if quirks is CrazyItems {
      return out
    }
    if obj.get("dependencies") is Some(Object(dependencies)) {
      // Only the *first* dependency's type is checked, exactly as upstream.
      let values = dependencies.values().to_array()
      if values is [Object(_), ..] {
        out.append(values)
      }
    }
    if quirks is CrazyAPItemsDependencies {
      for each in ["additionalItems", "additionalProperties"] {
        if obj.get(each) is Some(Object(_) as value) {
          out.push(value)
        }
      }
    }
    out
  }
}

///|
/// Which keywords' values always enter a subresource while following a JSON
/// pointer, in addition to the plain keyword sets.
priv enum PointerQuirks {
  /// draft 2020-12
  NoPointerQuirks
  /// draft 2019-09: `items` into an object enters a subresource
  ItemsPointer
  /// drafts 3 to 7: `items` / `dependencies` into an object
  ItemsDependenciesPointer
}

///|
fn make_maybe_in_subresource(
  in_value~ : Array[String],
  in_subvalues~ : Array[String],
  in_subarray~ : Array[String],
  quirks~ : PointerQuirks,
) -> (Array[Segment], Resolver, Resource) -> Resolver raise {
  let in_child = [..in_subvalues, ..in_subarray]
  (segments, resolver, subresource) => {
    let is_object = subresource.contents is Object(_)
    let mut i = 0
    while i < segments.length() {
      let segment = segments[i]
      i += 1
      let entering = match quirks {
        NoPointerQuirks => false
        ItemsPointer => segment.is_key("items")
        ItemsDependenciesPointer =>
          segment.is_key("items") || segment.is_key("dependencies")
      }
      if entering && is_object {
        return resolver.in_subresource(subresource)
      }
      let in_value_ = in_value.iter().any(k => segment.is_key(k))
      if !in_value_ {
        let in_child_ = in_child.iter().any(k => segment.is_key(k))
        if !in_child_ {
          return resolver
        }
        // `next(_segments, None) is None`: consume the child's key/index.
        if i >= segments.length() {
          return resolver
        }
        i += 1
      }
    }
    resolver.in_subresource(subresource)
  }
}
