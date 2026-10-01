// A port of `jsonschema/_legacy_keywords.py`.

///|
/// Ignore siblings of `$ref` if it is present; otherwise return all
/// keywords (upstream's `ignore_ref_siblings`, for `create`'s
/// `applicable_validators`).
pub fn ignore_ref_siblings(schema : Json) -> Array[(String, Json)] {
  match get_key(schema, "$ref") {
    Some(ref_) if !(ref_ is Null) => [("$ref", ref_)]
    _ => default_applicable(schema)
  }
}

///|
fn kw_dependencies_draft3(
  validator : Validator,
  dependencies : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    for entry in object_items(dependencies) {
      let (property, dependency) = entry
      if !obj.contains(property) {
        continue
      }
      if validator.is_type(dependency, "object") {
        if !validator
          .descend(instance, dependency, schema_path=Key(property))
          .run(yield_) {
          return false
        }
      } else if dependency is String(d) &&
        validator.is_type(dependency, "string") {
        if !obj.contains(d) {
          if !yield_(
              err(
                "\{r(dependency)} is a dependency of \{@pycompat.repr_string(property)}",
              ),
            ) {
            return false
          }
        }
      } else {
        for each in py_iter(dependency) {
          let present = match each {
            String(e) => obj.contains(e)
            _ => false
          }
          if !present {
            if !yield_(
                err(
                  "\{r(each)} is a dependency of \{@pycompat.repr_string(property)}",
                ),
              ) {
              return false
            }
          }
        }
      }
    }
    true
  })
}

///|
/// Support for the `dependencies` keyword from pre-draft 2019-09.
fn kw_dependencies_draft4_draft6_draft7(
  validator : Validator,
  dependencies : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    for entry in object_items(dependencies) {
      let (property, dependency) = entry
      if !obj.contains(property) {
        continue
      }
      if validator.is_type(dependency, "array") {
        for each in py_iter(dependency) {
          let present = match each {
            String(e) => obj.contains(e)
            _ => false
          }
          if !present {
            if !yield_(
                err(
                  "\{r(each)} is a dependency of \{@pycompat.repr_string(property)}",
                ),
              ) {
              return false
            }
          }
        }
      } else if !validator
        .descend(instance, dependency, schema_path=Key(property))
        .run(yield_) {
        return false
      }
    }
    true
  })
}

///|
fn kw_disallow_draft3(
  validator : Validator,
  disallow : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    for disallowed in ensure_list(disallow) {
      let schema = Json::object(
        Map::from_array([("type", Json::array([disallowed]))]),
      )
      if validator.evolve(schema~).is_valid(instance) {
        if !yield_(err("\{r(disallowed)} is disallowed for \{r(instance)}")) {
          return false
        }
      }
    }
    true
  })
}

///|
fn kw_extends_draft3(
  validator : Validator,
  extends : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.is_type(extends, "object") {
      return validator.descend(instance, extends).run(yield_)
    }
    for index, subschema in py_iter(extends) {
      if !validator
        .descend(instance, subschema, schema_path=Index(index))
        .run(yield_) {
        return false
      }
    }
    true
  })
}

///|
fn kw_items_draft3_draft4(
  validator : Validator,
  items : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Array(xs) && validator.is_type(instance, "array") else {
      return true
    }
    if validator.is_type(items, "object") {
      for index, item in xs {
        if !validator.descend(item, items, path=Index(index)).run(yield_) {
          return false
        }
      }
    } else {
      let subschemas = py_iter(items)
      for index, item in xs {
        if index >= subschemas.length() {
          break
        }
        let ok = validator
          .descend(
            item,
            subschemas[index],
            path=Index(index),
            schema_path=Index(index),
          )
          .run(yield_)
        if !ok {
          return false
        }
      }
    }
    true
  })
}

///|
fn kw_additional_items(
  validator : Validator,
  ai : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    let items = get_key(schema, "items").unwrap_or(Json::empty_object())
    guard instance is Array(xs) &&
      validator.is_type(instance, "array") &&
      !validator.is_type(items, "object") else {
      return true
    }
    let len_items = match get_key(schema, "items") {
      Some(i) => py_len(i)
      None => 0
    }
    if validator.is_type(ai, "object") {
      for index in len_items..<xs.length() {
        if !validator.descend(xs[index], ai, path=Index(index)).run(yield_) {
          return false
        }
      }
    } else if !truthy(ai) && xs.length() > len_items {
      let (extras, verb) = extras_msg(xs[len_items:])
      return yield_(
        err("Additional items are not allowed (\{extras} \{verb} unexpected)"),
      )
    }
    true
  })
}

///|
fn kw_items_draft6_draft7_draft201909(
  validator : Validator,
  items : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Array(xs) && validator.is_type(instance, "array") else {
      return true
    }
    if validator.is_type(items, "array") {
      let subschemas = py_iter(items)
      for index, item in xs {
        if index >= subschemas.length() {
          break
        }
        let ok = validator
          .descend(
            item,
            subschemas[index],
            path=Index(index),
            schema_path=Index(index),
          )
          .run(yield_)
        if !ok {
          return false
        }
      }
    } else {
      for index, item in xs {
        if !validator.descend(item, items, path=Index(index)).run(yield_) {
          return false
        }
      }
    }
    true
  })
}

///|
fn kw_minimum_draft3_draft4(
  validator : Validator,
  minimum : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "number") {
      return true
    }
    let (failed, cmp) = if truthy(
        get_key(schema, "exclusiveMinimum").unwrap_or(Json::boolean(false)),
      ) {
      (py_le(instance, minimum), "less than or equal to")
    } else {
      (py_lt(instance, minimum), "less than")
    }
    if failed {
      return yield_(
        err("\{r(instance)} is \{cmp} the minimum of \{r(minimum)}"),
      )
    }
    true
  })
}

///|
fn kw_maximum_draft3_draft4(
  validator : Validator,
  maximum : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "number") {
      return true
    }
    let (failed, cmp) = if truthy(
        get_key(schema, "exclusiveMaximum").unwrap_or(Json::boolean(false)),
      ) {
      (py_ge(instance, maximum), "greater than or equal to")
    } else {
      (py_gt(instance, maximum), "greater than")
    }
    if failed {
      return yield_(
        err("\{r(instance)} is \{cmp} the maximum of \{r(maximum)}"),
      )
    }
    true
  })
}

///|
fn kw_properties_draft3(
  validator : Validator,
  properties : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    for entry in object_items(properties) {
      let (property, subschema) = entry
      if obj.get(property) is Some(value) {
        let ok = validator
          .descend(
            value,
            subschema,
            path=Key(property),
            schema_path=Key(property),
          )
          .run(yield_)
        if !ok {
          return false
        }
      } else if get_key(subschema, "required") is Some(required) &&
        truthy(required) {
        let error = err(
          "\{@pycompat.repr_string(property)} is a required property",
        )
        if error.validator is None {
          error.validator = Some(Json::string("required"))
        }
        if error.validator_value is None {
          error.validator_value = Some(required)
        }
        if error.instance is None {
          error.instance = Some(instance)
        }
        if error.schema is None {
          error.schema = Some(schema)
        }
        error.path.insert(0, Key(property))
        error.schema_path.push(Key(property))
        error.schema_path.push(Key("required"))
        if !yield_(error) {
          return false
        }
      }
    }
    true
  })
}

///|
fn kw_type_draft3(
  validator : Validator,
  types : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    let types = ensure_list(types)
    let all_errors = []
    for index, t in types {
      if validator.is_type(t, "object") {
        let errors = validator
          .descend(instance, t, schema_path=Index(index))
          .to_array()
        if errors.is_empty() {
          return true
        }
        all_errors.append(errors)
      } else {
        guard t is String(name) else {
          raise PythonError("TypeError: unhashable type: \{type_name(t)}")
        }
        if validator.is_type(instance, name) {
          return true
        }
      }
    }
    let reprs = types.map(t => {
      match t {
        Object({ "name": name, .. }) => r(name)
        _ => r(t)
      }
    })
    yield_(
      ValidationError::new(
        "\{r(instance)} is not of type \{reprs.join(", ")}",
        context=all_errors,
      ),
    )
  })
}

///|
fn kw_contains_draft6_draft7(
  validator : Validator,
  contains : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Array(xs) && validator.is_type(instance, "array") else {
      return true
    }
    let contains_validator = validator.evolve(schema=contains)
    for element in xs {
      if contains_validator.is_valid(element) {
        return true
      }
    }
    yield_(err("None of \{r(instance)} are valid under the given schema"))
  })
}

///|
fn kw_recursive_ref(
  validator : Validator,
  _recursive_ref : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    let resolved = @referencing.lookup_recursive_ref(validator.resolver)
    validator
    .descend(instance, resolved.contents, resolver=resolved.resolver)
    .run(yield_)
  })
}

///|
fn kw_unevaluated_items_draft2019(
  validator : Validator,
  _unevaluated_items : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Array(xs) && validator.is_type(instance, "array") else {
      return true
    }
    let evaluated = find_evaluated_item_indexes_by_schema_2019(
      validator, instance, schema,
    )
    let unevaluated = []
    for index, item in xs {
      if !evaluated.contains(index) {
        unevaluated.push(item)
      }
    }
    if unevaluated.length() > 0 {
      let (extras, verb) = extras_msg(unevaluated)
      return yield_(
        err("Unevaluated items are not allowed (\{extras} \{verb} unexpected)"),
      )
    }
    true
  })
}

///|
fn kw_unevaluated_properties_draft2019(
  validator : Validator,
  up : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    let evaluated_keys = find_evaluated_property_keys_by_schema_2019(
      validator, instance, schema,
    )
    unevaluated_properties_errors(validator, up, obj, evaluated_keys, yield_)
  })
}
