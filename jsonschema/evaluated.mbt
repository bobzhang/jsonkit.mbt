// The `unevaluatedItems` / `unevaluatedProperties` helpers of
// `jsonschema/_utils.py` (draft 2020-12) and `jsonschema/_legacy_keywords.py`
// (draft 2019-09).

///|
fn range_indexes(n : Int) -> Array[Int] {
  Array::makei(n, i => i)
}

///|
/// Get all indexes of items that get evaluated under the current schema
/// (draft 2020-12).
fn find_evaluated_item_indexes_by_schema(
  validator : Validator,
  instance : Json,
  schema : Json,
) -> Array[Int] raise {
  if validator.is_type(schema, "boolean") {
    return []
  }
  let evaluated_indexes = []
  if has_key(schema, "items") {
    return range_indexes(py_len(instance))
  }
  if get_key(schema, "$ref") is Some(ref_) && !(ref_ is Null) {
    guard ref_ is String(ref_) else { raise PythonError("TypeError: bad $ref") }
    let resolved = validator.resolver.lookup(ref_)
    evaluated_indexes.append(
      find_evaluated_item_indexes_by_schema(
        validator.evolve(schema=resolved.contents, resolver=resolved.resolver),
        instance,
        resolved.contents,
      ),
    )
  }
  if get_key(schema, "$dynamicRef") is Some(dynamic_ref) &&
    !(dynamic_ref is Null) {
    guard dynamic_ref is String(dynamic_ref) else {
      raise PythonError("TypeError: bad $dynamicRef")
    }
    let resolved = validator.resolver.lookup(dynamic_ref)
    evaluated_indexes.append(
      find_evaluated_item_indexes_by_schema(
        validator.evolve(schema=resolved.contents, resolver=resolved.resolver),
        instance,
        resolved.contents,
      ),
    )
  }
  if get_key(schema, "prefixItems") is Some(prefix_items) {
    evaluated_indexes.append(range_indexes(py_len(prefix_items)))
  }
  if get_key(schema, "if") is Some(if_schema) {
    if validator.evolve(schema=if_schema).is_valid(instance) {
      evaluated_indexes.append(
        find_evaluated_item_indexes_by_schema(validator, instance, if_schema),
      )
      if get_key(schema, "then") is Some(then) {
        evaluated_indexes.append(
          find_evaluated_item_indexes_by_schema(validator, instance, then),
        )
      }
    } else if get_key(schema, "else") is Some(else_) {
      evaluated_indexes.append(
        find_evaluated_item_indexes_by_schema(validator, instance, else_),
      )
    }
  }
  for keyword in ["contains", "unevaluatedItems"] {
    if get_key(schema, keyword) is Some(subschema) {
      for k, v in py_iter(instance) {
        if validator.evolve(schema=subschema).is_valid(v) {
          evaluated_indexes.push(k)
        }
      }
    }
  }
  for keyword in ["allOf", "oneOf", "anyOf"] {
    if get_key(schema, keyword) is Some(subschemas) {
      for subschema in py_iter(subschemas) {
        if validator.descend(instance, subschema).is_empty() {
          evaluated_indexes.append(
            find_evaluated_item_indexes_by_schema(
              validator, instance, subschema,
            ),
          )
        }
      }
    }
  }
  evaluated_indexes
}

///|
/// Get all keys of items that get evaluated under the current schema
/// (draft 2020-12).
fn find_evaluated_property_keys_by_schema(
  validator : Validator,
  instance : Json,
  schema : Json,
) -> Array[String] raise {
  if validator.is_type(schema, "boolean") {
    return []
  }
  let evaluated_keys = []
  if get_key(schema, "$ref") is Some(ref_) && !(ref_ is Null) {
    guard ref_ is String(ref_) else { raise PythonError("TypeError: bad $ref") }
    let resolved = validator.resolver.lookup(ref_)
    evaluated_keys.append(
      find_evaluated_property_keys_by_schema(
        validator.evolve(schema=resolved.contents, resolver=resolved.resolver),
        instance,
        resolved.contents,
      ),
    )
  }
  if get_key(schema, "$dynamicRef") is Some(dynamic_ref) &&
    !(dynamic_ref is Null) {
    guard dynamic_ref is String(dynamic_ref) else {
      raise PythonError("TypeError: bad $dynamicRef")
    }
    let resolved = validator.resolver.lookup(dynamic_ref)
    evaluated_keys.append(
      find_evaluated_property_keys_by_schema(
        validator.evolve(schema=resolved.contents, resolver=resolved.resolver),
        instance,
        resolved.contents,
      ),
    )
  }
  evaluated_property_keys_common(
    validator, instance, schema, evaluated_keys, find_evaluated_property_keys_by_schema,
  )
  evaluated_keys
}

///|
/// The part of the property-key helpers shared by both drafts (the
/// draft-specific order of `allOf`... vs `if` is preserved by each caller).
fn evaluated_property_keys_common(
  validator : Validator,
  instance : Json,
  schema : Json,
  evaluated_keys : Array[String],
  recurse : (Validator, Json, Json) -> Array[String] raise,
) -> Unit raise {
  guard instance is Object(obj) else {
    raise PythonError("AttributeError: object has no attribute 'keys'")
  }
  if get_key(schema, "properties") is Some(properties) &&
    validator.is_type(properties, "object") {
    for entry in object_items(properties) {
      if obj.contains(entry.0) {
        evaluated_keys.push(entry.0)
      }
    }
  }
  for keyword in ["additionalProperties", "unevaluatedProperties"] {
    guard get_key(schema, keyword) is Some(subschema) && !(subschema is Null) else {
      continue
    }
    for key, value in obj {
      if validator.descend(value, subschema).is_empty() {
        evaluated_keys.push(key)
      }
    }
  }
  if get_key(schema, "patternProperties") is Some(pattern_properties) {
    for property, _ in obj {
      for pattern in py_iter(pattern_properties) {
        if @regex.search(py_str(pattern), property) {
          evaluated_keys.push(property)
        }
      }
    }
  }
  if get_key(schema, "dependentSchemas") is Some(dependent_schemas) {
    for entry in object_items(dependent_schemas) {
      let (property, subschema) = entry
      if !obj.contains(property) {
        continue
      }
      evaluated_keys.append(recurse(validator, instance, subschema))
    }
  }
  for keyword in ["allOf", "oneOf", "anyOf"] {
    if get_key(schema, keyword) is Some(subschemas) {
      for subschema in py_iter(subschemas) {
        if !validator.descend(instance, subschema).is_empty() {
          continue
        }
        evaluated_keys.append(recurse(validator, instance, subschema))
      }
    }
  }
  if get_key(schema, "if") is Some(if_schema) {
    if validator.evolve(schema=if_schema).is_valid(instance) {
      evaluated_keys.append(recurse(validator, instance, if_schema))
      if get_key(schema, "then") is Some(then) {
        evaluated_keys.append(recurse(validator, instance, then))
      }
    } else if get_key(schema, "else") is Some(else_) {
      evaluated_keys.append(recurse(validator, instance, else_))
    }
  }
}

///|
/// Draft 2019-09's `find_evaluated_item_indexes_by_schema`.
fn find_evaluated_item_indexes_by_schema_2019(
  validator : Validator,
  instance : Json,
  schema : Json,
) -> Array[Int] raise {
  if validator.is_type(schema, "boolean") {
    return []
  }
  let evaluated_indexes = []
  if get_key(schema, "$ref") is Some(ref_) && !(ref_ is Null) {
    guard ref_ is String(ref_) else { raise PythonError("TypeError: bad $ref") }
    let resolved = validator.resolver.lookup(ref_)
    evaluated_indexes.append(
      find_evaluated_item_indexes_by_schema_2019(
        validator.evolve(schema=resolved.contents, resolver=resolved.resolver),
        instance,
        resolved.contents,
      ),
    )
  }
  if has_key(schema, "$recursiveRef") {
    let resolved = @referencing.lookup_recursive_ref(validator.resolver)
    evaluated_indexes.append(
      find_evaluated_item_indexes_by_schema_2019(
        validator.evolve(schema=resolved.contents, resolver=resolved.resolver),
        instance,
        resolved.contents,
      ),
    )
  }
  if get_key(schema, "items") is Some(items) {
    if has_key(schema, "additionalItems") {
      return range_indexes(py_len(instance))
    }
    if validator.is_type(items, "object") {
      return range_indexes(py_len(instance))
    }
    evaluated_indexes.append(range_indexes(py_len(items)))
  }
  if get_key(schema, "if") is Some(if_schema) {
    if validator.evolve(schema=if_schema).is_valid(instance) {
      evaluated_indexes.append(
        find_evaluated_item_indexes_by_schema_2019(
          validator, instance, if_schema,
        ),
      )
      if get_key(schema, "then") is Some(then) {
        evaluated_indexes.append(
          find_evaluated_item_indexes_by_schema_2019(validator, instance, then),
        )
      }
    } else if get_key(schema, "else") is Some(else_) {
      evaluated_indexes.append(
        find_evaluated_item_indexes_by_schema_2019(validator, instance, else_),
      )
    }
  }
  for keyword in ["contains", "unevaluatedItems"] {
    if get_key(schema, keyword) is Some(subschema) {
      for k, v in py_iter(instance) {
        if validator.evolve(schema=subschema).is_valid(v) {
          evaluated_indexes.push(k)
        }
      }
    }
  }
  for keyword in ["allOf", "oneOf", "anyOf"] {
    if get_key(schema, keyword) is Some(subschemas) {
      for subschema in py_iter(subschemas) {
        if validator.descend(instance, subschema).is_empty() {
          evaluated_indexes.append(
            find_evaluated_item_indexes_by_schema_2019(
              validator, instance, subschema,
            ),
          )
        }
      }
    }
  }
  evaluated_indexes
}

///|
/// Draft 2019-09's `find_evaluated_property_keys_by_schema`.
fn find_evaluated_property_keys_by_schema_2019(
  validator : Validator,
  instance : Json,
  schema : Json,
) -> Array[String] raise {
  if validator.is_type(schema, "boolean") {
    return []
  }
  let evaluated_keys = []
  if get_key(schema, "$ref") is Some(ref_) && !(ref_ is Null) {
    guard ref_ is String(ref_) else { raise PythonError("TypeError: bad $ref") }
    let resolved = validator.resolver.lookup(ref_)
    evaluated_keys.append(
      find_evaluated_property_keys_by_schema_2019(
        validator.evolve(schema=resolved.contents, resolver=resolved.resolver),
        instance,
        resolved.contents,
      ),
    )
  }
  if has_key(schema, "$recursiveRef") {
    let resolved = @referencing.lookup_recursive_ref(validator.resolver)
    evaluated_keys.append(
      find_evaluated_property_keys_by_schema_2019(
        validator.evolve(schema=resolved.contents, resolver=resolved.resolver),
        instance,
        resolved.contents,
      ),
    )
  }
  evaluated_property_keys_common(
    validator, instance, schema, evaluated_keys, find_evaluated_property_keys_by_schema_2019,
  )
  evaluated_keys
}
