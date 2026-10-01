// The JSON Schema specifications (Python's `referencing.jsonschema`).
//
// These live in the root package (rather than only in
// `bobzhang/referencing/jsonschema`) because `Specification::detect` /
// `Resource::from_contents` need `specification_with`, and MoonBit packages
// cannot be mutually dependent. `bobzhang/referencing/jsonschema` re-exports
// them under the upstream module layout.

///|
fn draft_specification(
  name~ : String,
  id_of~ : (Json) -> String?,
  anchors_in~ : (Specification, Json) -> Array[Anchor],
  in_value~ : Array[String],
  in_subarray~ : Array[String],
  in_subvalues~ : Array[String],
  quirks~ : Quirks,
  pointer_in_value? : Array[String] = in_value,
  pointer_quirks~ : PointerQuirks,
) -> Specification {
  Specification::new(
    name~,
    id_of~,
    subresources_of=make_subresources_of(
      in_value~,
      in_subarray~,
      in_subvalues~,
      quirks~,
    ),
    anchors_in~,
    maybe_in_subresource=make_maybe_in_subresource(
      in_value=pointer_in_value,
      in_subarray~,
      in_subvalues~,
      quirks=pointer_quirks,
    ),
  )
}

///|
/// JSON Schema draft 2020-12.
pub fn draft202012() -> Specification {
  cached_specification("draft202012", () => draft_specification(
  name="draft2020-12",
  id_of=dollar_id,
  anchors_in=anchors_2020,
  in_value=[
    "additionalProperties", "contains", "contentSchema", "else", "if", "items", "not",
    "propertyNames", "then", "unevaluatedItems", "unevaluatedProperties",
  ],
  in_subarray=["allOf", "anyOf", "oneOf", "prefixItems"],
  in_subvalues=[
    "$defs", "definitions", "dependentSchemas", "patternProperties", "properties",
  ],
  quirks=NoQuirks,
  pointer_quirks=NoPointerQuirks,
  ))
}

///|
/// JSON Schema draft 2019-09.
pub fn draft201909() -> Specification {
  cached_specification("draft201909", () => draft_specification(
  name="draft2019-09",
  id_of=dollar_id,
  anchors_in=anchors_2019,
  in_value=[
    "additionalItems", "additionalProperties", "contains", "contentSchema", "else",
    "if", "not", "propertyNames", "then", "unevaluatedItems", "unevaluatedProperties",
  ],
  in_subarray=["allOf", "anyOf", "oneOf"],
  in_subvalues=[
    "$defs", "definitions", "dependentSchemas", "patternProperties", "properties",
  ],
  quirks=CrazyItems,
  pointer_quirks=ItemsPointer,
  ))
}

///|
/// JSON Schema draft 7.
pub fn draft7() -> Specification {
  cached_specification("draft7", () => draft_specification(
  name="draft-07",
  id_of=legacy_dollar_id,
  anchors_in=legacy_anchor_in_dollar_id,
  in_value=[
    "additionalItems", "additionalProperties", "contains", "else", "if", "not", "propertyNames",
    "then",
  ],
  in_subarray=["allOf", "anyOf", "oneOf"],
  in_subvalues=["definitions", "patternProperties", "properties"],
  quirks=CrazyItemsDependencies,
  pointer_quirks=ItemsDependenciesPointer,
  ))
}

///|
/// JSON Schema draft 6.
pub fn draft6() -> Specification {
  cached_specification("draft6", () => draft_specification(
  name="draft-06",
  id_of=legacy_dollar_id,
  anchors_in=legacy_anchor_in_dollar_id,
  in_value=[
    "additionalItems", "additionalProperties", "contains", "not", "propertyNames",
  ],
  in_subarray=["allOf", "anyOf", "oneOf"],
  in_subvalues=["definitions", "patternProperties", "properties"],
  quirks=CrazyItemsDependencies,
  pointer_quirks=ItemsDependenciesPointer,
  ))
}

///|
/// JSON Schema draft 4.
pub fn draft4() -> Specification {
  cached_specification("draft4", () => draft_specification(
  name="draft-04",
  id_of=legacy_id,
  anchors_in=legacy_anchor_in_id,
  in_value=["not"],
  pointer_in_value=["additionalItems", "additionalProperties", "not"],
  in_subarray=["allOf", "anyOf", "oneOf"],
  in_subvalues=["definitions", "patternProperties", "properties"],
  quirks=CrazyAPItemsDependencies,
  pointer_quirks=ItemsDependenciesPointer,
  ))
}

///|
/// JSON Schema draft 3.
pub fn draft3() -> Specification {
  cached_specification("draft3", () => draft_specification(
  name="draft-03",
  id_of=legacy_id,
  anchors_in=legacy_anchor_in_id,
  in_value=[],
  pointer_in_value=["additionalItems", "additionalProperties"],
  in_subarray=["extends"],
  in_subvalues=["definitions", "patternProperties", "properties"],
  quirks=CrazyAPItemsDependencies,
  pointer_quirks=ItemsDependenciesPointer,
  ))
}

///|
/// The specification for a known dialect identifier (without trailing `#`).
fn known_specification(dialect_id : String) -> Specification? {
  match dialect_id {
    "https://json-schema.org/draft/2020-12/schema" => Some(draft202012())
    "https://json-schema.org/draft/2019-09/schema" => Some(draft201909())
    "http://json-schema.org/draft-07/schema" => Some(draft7())
    "http://json-schema.org/draft-06/schema" => Some(draft6())
    "http://json-schema.org/draft-04/schema" => Some(draft4())
    "http://json-schema.org/draft-03/schema" => Some(draft3())
    _ => None
  }
}

///|
/// The specifications are built lazily (once) rather than being top-level
/// `let`s, since their callbacks (transitively) refer back to
/// `specification_with`, which MoonBit rejects as a definition cycle among
/// top-level values. Each function always returns the very same object.
let specification_cache : Map[String, Specification] = Map([])

///|
fn cached_specification(
  key : String,
  build : () -> Specification,
) -> Specification {
  match specification_cache.get(key) {
    Some(specification) => specification
    None => {
      let specification = build()
      specification_cache[key] = specification
      specification
    }
  }
}

///|
/// The empty JSON Schema registry (Python's `EMPTY_REGISTRY`).
pub let empty_registry : Registry = Registry::new()

///|
/// Retrieve the `Specification` with the given dialect identifier (trailing
/// `#`s are ignored).
///
/// Raises `UnknownDialect` if the given `dialect_id` isn't known and no
/// `default` is given.
///
/// ```mbt check
/// test {
///   let spec = @referencing.specification_with(
///     "http://json-schema.org/draft-07/schema#",
///   )
///   inspect(spec, content="<Specification name='draft-07'>")
/// }
/// ```
pub fn specification_with(
  dialect_id : String,
  default? : Specification,
) -> Specification raise ReferencingError {
  match known_specification(rstrip_hash(dialect_id)) {
    Some(specification) => specification
    None =>
      match default {
        Some(default) => default
        None => raise UnknownDialect(uri=dialect_id)
      }
  }
}

///|
/// Create a dynamic anchor, introduced in draft 2020-12 (Python's
/// `DynamicAnchor(name=..., resource=...)`). Its `kind` is `"DynamicAnchor"`.
///
/// Resolving it walks the resolver's dynamic scope (outermost last), taking
/// the outermost resource which also declares a dynamic anchor with this
/// name, and enters it as a subresource.
pub fn dynamic_anchor(name~ : String, resource~ : Resource) -> Anchor {
  Anchor::custom(name~, resource~, kind="DynamicAnchor", resolve=resolve_dynamic)
}

///|
/// Whether this anchor is a `DynamicAnchor` (Python's
/// `isinstance(anchor, DynamicAnchor)`).
pub fn Anchor::is_dynamic(self : Anchor) -> Bool {
  self.kind() == "DynamicAnchor"
}

///|
/// Python's `DynamicAnchor.resolve`.
fn resolve_dynamic(anchor_ : Anchor, resolver : Resolver) -> Resolved raise {
  let mut last = anchor_.resource
  for scope in resolver.dynamic_scope() {
    let (uri, registry) = scope
    let anchor = registry.anchor(uri, anchor_.name) catch {
      NoSuchAnchor(..) => continue
      error => raise error
    }
    if anchor.value.is_dynamic() {
      last = anchor.value.resource
    }
  }
  { contents: last.contents, resolver: resolver.in_subresource(last) }
}

///|
/// Recursive references (via recursive anchors), present only in draft
/// 2019-09.
///
/// As per the 2019 specification (§ 8.2.4.2.1), only the `#` recursive
/// reference is supported (and is therefore assumed to be the relevant
/// reference).
pub fn lookup_recursive_ref(resolver : Resolver) -> Resolved raise {
  let mut resolved = resolver.lookup("#")
  if has_truthy_recursive_anchor(resolved.contents) {
    for scope in resolver.dynamic_scope() {
      let next_resolved = resolver.lookup(scope.0)
      if !has_truthy_recursive_anchor(next_resolved.contents) {
        break
      }
      resolved = next_resolved
    }
  }
  resolved
}

///|
fn has_truthy_recursive_anchor(contents : Json) -> Bool {
  contents is Object(obj) &&
  obj.get("$recursiveAnchor") is Some(value) &&
  py_truthy(value)
}
