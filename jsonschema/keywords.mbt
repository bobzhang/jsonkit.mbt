// A port of `jsonschema/_keywords.py`.

///|
fn err(message : String) -> ValidationError {
  ValidationError::new(message)
}

///|
fn r(j : Json) -> String {
  @pycompat.repr(j)
}

///|
fn object_items(j : Json) -> Array[(String, Json)] {
  match j {
    Object(m) => m.iter().collect()
    _ => []
  }
}

///|
fn kw_pattern_properties(
  validator : Validator,
  pattern_properties : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "object") {
      return true
    }
    for entry in object_items(pattern_properties) {
      let (pattern, subschema) = entry
      for item in object_items(instance) {
        let (k, v) = item
        if @regex.search(pattern, k) {
          let ok = validator
            .descend(v, subschema, path=Key(k), schema_path=Key(pattern))
            .run(yield_)
          if !ok {
            return false
          }
        }
      }
    }
    true
  })
}

///|
fn kw_property_names(
  validator : Validator,
  property_names : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "object") {
      return true
    }
    for item in object_items(instance) {
      if !validator.descend(Json::string(item.0), property_names).run(yield_) {
        return false
      }
    }
    true
  })
}

///|
fn kw_additional_properties(
  validator : Validator,
  additional : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    let extras = find_additional_properties(obj, schema)
    if validator.is_type(additional, "object") {
      for extra in extras {
        if !validator
          .descend(obj[extra], additional, path=Key(extra))
          .run(yield_) {
          return false
        }
      }
    } else if !truthy(additional) && extras.length() > 0 {
      if has_key(schema, "patternProperties") {
        let verb = if extras.length() == 1 { "does" } else { "do" }
        let joined = py_sorted(extras)
          .map(e => @pycompat.repr_string(e))
          .join(", ")
        let patterns = py_sorted(
            object_items(get_key(schema, "patternProperties").unwrap()).map(p => {
              p.0
            }),
          )
          .map(p => @pycompat.repr_string(p))
          .join(", ")
        return yield_(
          err("\{joined} \{verb} not match any of the regexes: \{patterns}"),
        )
      } else {
        let (extras_repr, verb) = extras_msg(
          py_sorted(extras).map(e => Json::string(e)),
        )
        return yield_(
          err(
            "Additional properties are not allowed (\{extras_repr} \{verb} unexpected)",
          ),
        )
      }
    }
    true
  })
}

///|
fn kw_items(
  validator : Validator,
  items : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Array(xs) && validator.is_type(instance, "array") else {
      return true
    }
    let prefix = match get_key(schema, "prefixItems") {
      Some(p) => py_len(p)
      None => 0
    }
    let total = xs.length()
    let extra = total - prefix
    if extra <= 0 {
      return true
    }
    if items is False {
      let rest = if extra != 1 {
        Json::array(xs[prefix:].to_owned())
      } else {
        xs[prefix]
      }
      let item = if prefix != 1 { "items" } else { "item" }
      return yield_(
        err(
          "Expected at most \{prefix} \{item} but found \{extra} extra: \{r(rest)}",
        ),
      )
    }
    for index in prefix..<total {
      if !validator.descend(xs[index], items, path=Index(index)).run(yield_) {
        return false
      }
    }
    true
  })
}

///|
fn kw_const(
  _validator : Validator,
  const_ : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !equal(instance, const_) {
      return yield_(err("\{r(const_)} was expected"))
    }
    true
  })
}

///|
fn kw_contains(
  validator : Validator,
  contains : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Array(xs) && validator.is_type(instance, "array") else {
      return true
    }
    let mut matches = 0
    let min_contains = get_key(schema, "minContains").unwrap_or(int_json(1))
    let max_contains = get_key(schema, "maxContains").unwrap_or(
      int_json(xs.length()),
    )
    let contains_validator = validator.evolve(schema=contains)
    for each in xs {
      if contains_validator.is_valid(each) {
        matches += 1
        if py_gt(int_json(matches), max_contains) {
          return yield_(
            ValidationError::new(
              "Too many items match the given schema (expected at most \{py_str(max_contains)})",
              validator=Json::string("maxContains"),
              validator_value=max_contains,
            ),
          )
        }
      }
    }
    if py_lt(int_json(matches), min_contains) {
      if matches == 0 {
        return yield_(
          err("\{r(instance)} does not contain items matching the given schema"),
        )
      } else {
        return yield_(
          ValidationError::new(
            "Too few items match the given schema (expected at least \{py_str(min_contains)} but only \{matches} matched)",
            validator=Json::string("minContains"),
            validator_value=min_contains,
          ),
        )
      }
    }
    true
  })
}

///|
fn kw_exclusive_minimum(
  validator : Validator,
  minimum : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "number") {
      return true
    }
    if py_le(instance, minimum) {
      return yield_(
        err(
          "\{r(instance)} is less than or equal to the minimum of \{r(minimum)}",
        ),
      )
    }
    true
  })
}

///|
fn kw_exclusive_maximum(
  validator : Validator,
  maximum : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "number") {
      return true
    }
    if py_ge(instance, maximum) {
      return yield_(
        err(
          "\{r(instance)} is greater than or equal to the maximum of \{r(maximum)}",
        ),
      )
    }
    true
  })
}

///|
fn kw_minimum(
  validator : Validator,
  minimum : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "number") {
      return true
    }
    if py_lt(instance, minimum) {
      return yield_(
        err("\{r(instance)} is less than the minimum of \{r(minimum)}"),
      )
    }
    true
  })
}

///|
fn kw_maximum(
  validator : Validator,
  maximum : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "number") {
      return true
    }
    if py_gt(instance, maximum) {
      return yield_(
        err("\{r(instance)} is greater than the maximum of \{r(maximum)}"),
      )
    }
    true
  })
}

///|
fn kw_multiple_of(
  validator : Validator,
  db : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "number") {
      return true
    }
    if @pycompat.multiple_of_failed(instance, db) {
      return yield_(err("\{r(instance)} is not a multiple of \{py_str(db)}"))
    }
    true
  })
}

///|
fn kw_min_items(
  validator : Validator,
  mi : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.is_type(instance, "array") &&
      py_lt(int_json(py_len(instance)), mi) {
      let message = if @pycompat.numbers_equal(mi, int_json(1)) {
        "should be non-empty"
      } else {
        "is too short"
      }
      return yield_(err("\{r(instance)} \{message}"))
    }
    true
  })
}

///|
fn kw_max_items(
  validator : Validator,
  mi : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.is_type(instance, "array") &&
      py_gt(int_json(py_len(instance)), mi) {
      let message = if @pycompat.numbers_equal(mi, int_json(0)) {
        "is expected to be empty"
      } else {
        "is too long"
      }
      return yield_(err("\{r(instance)} \{message}"))
    }
    true
  })
}

///|
fn kw_unique_items(
  validator : Validator,
  ui : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if truthy(ui) &&
      validator.is_type(instance, "array") &&
      instance is Array(xs) &&
      !uniq(xs) {
      return yield_(err("\{r(instance)} has non-unique elements"))
    }
    true
  })
}

///|
fn kw_pattern(
  validator : Validator,
  patrn : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.is_type(instance, "string") && instance is String(s) {
      guard patrn is String(p) else {
        raise PythonError(
          "TypeError: first argument must be string or compiled pattern",
        )
      }
      if !@regex.search(p, s) {
        return yield_(err("\{r(instance)} does not match \{r(patrn)}"))
      }
    }
    true
  })
}

///|
fn kw_format(
  validator : Validator,
  format : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard validator.format_checker is Some(checker) && format is String(f) else {
      return true
    }
    checker.check(instance, f) catch {
      FormatError(message~, cause~) =>
        return yield_(ValidationError::new(message, cause?))
      e => raise e
    }
    true
  })
}

///|
fn kw_min_length(
  validator : Validator,
  ml : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.is_type(instance, "string") &&
      py_lt(int_json(py_len(instance)), ml) {
      let message = if @pycompat.numbers_equal(ml, int_json(1)) {
        "should be non-empty"
      } else {
        "is too short"
      }
      return yield_(err("\{r(instance)} \{message}"))
    }
    true
  })
}

///|
fn kw_max_length(
  validator : Validator,
  ml : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.is_type(instance, "string") &&
      py_gt(int_json(py_len(instance)), ml) {
      let message = if @pycompat.numbers_equal(ml, int_json(0)) {
        "is expected to be empty"
      } else {
        "is too long"
      }
      return yield_(err("\{r(instance)} \{message}"))
    }
    true
  })
}

///|
fn kw_dependent_required(
  validator : Validator,
  dependent_required : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    for entry in object_items(dependent_required) {
      let (property, dependency) = entry
      if !obj.contains(property) {
        continue
      }
      for each in py_iter(dependency) {
        if !has_key(instance, py_str(each)) || !(each is String(_)) {
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
    true
  })
}

///|
fn kw_dependent_schemas(
  validator : Validator,
  dependent_schemas : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    for entry in object_items(dependent_schemas) {
      let (property, dependency) = entry
      if !obj.contains(property) {
        continue
      }
      if !validator
        .descend(instance, dependency, schema_path=Key(property))
        .run(yield_) {
        return false
      }
    }
    true
  })
}

///|
fn kw_enum(
  _validator : Validator,
  enums : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if py_iter(enums).iter().all(each => !equal(each, instance)) {
      return yield_(err("\{r(instance)} is not one of \{r(enums)}"))
    }
    true
  })
}

///|
fn kw_ref(
  validator : Validator,
  ref_ : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard ref_ is String(s) else {
      raise PythonError("TypeError: $ref must be a string")
    }
    validator.validate_reference(s, instance).run(yield_)
  })
}

///|
fn kw_dynamic_ref(
  validator : Validator,
  dynamic_ref : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard dynamic_ref is String(s) else {
      raise PythonError("TypeError: $dynamicRef must be a string")
    }
    validator.validate_reference(s, instance).run(yield_)
  })
}

///|
fn kw_type(
  validator : Validator,
  types : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    let types = ensure_list(types)
    for t in types {
      guard t is String(name) else {
        raise PythonError("TypeError: unhashable type: \{type_name(t)}")
      }
      if validator.is_type(instance, name) {
        return true
      }
    }
    let reprs = types.map(r).join(", ")
    yield_(err("\{r(instance)} is not of type \{reprs}"))
  })
}

///|
fn kw_properties(
  validator : Validator,
  properties : Json,
  instance : Json,
  _schema : Json,
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
      }
    }
    true
  })
}

///|
fn kw_required(
  validator : Validator,
  required : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    for property in py_iter(required) {
      let present = match property {
        String(p) => obj.contains(p)
        _ => false
      }
      if !present {
        if !yield_(err("\{r(property)} is a required property")) {
          return false
        }
      }
    }
    true
  })
}

///|
fn kw_min_properties(
  validator : Validator,
  mp : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.is_type(instance, "object") &&
      py_lt(int_json(py_len(instance)), mp) {
      let message = if @pycompat.numbers_equal(mp, int_json(1)) {
        "should be non-empty"
      } else {
        "does not have enough properties"
      }
      return yield_(err("\{r(instance)} \{message}"))
    }
    true
  })
}

///|
fn kw_max_properties(
  validator : Validator,
  mp : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if !validator.is_type(instance, "object") {
      return true
    }
    if validator.is_type(instance, "object") &&
      py_gt(int_json(py_len(instance)), mp) {
      let message = if @pycompat.numbers_equal(mp, int_json(0)) {
        "is expected to be empty"
      } else {
        "has too many properties"
      }
      return yield_(err("\{r(instance)} \{message}"))
    }
    true
  })
}

///|
fn kw_all_of(
  validator : Validator,
  all_of : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    for index, subschema in py_iter(all_of) {
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
fn kw_any_of(
  validator : Validator,
  any_of : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    let all_errors = []
    for index, subschema in py_iter(any_of) {
      let errs = validator
        .descend(instance, subschema, schema_path=Index(index))
        .to_array()
      if errs.is_empty() {
        return true
      }
      all_errors.append(errs)
    }
    yield_(
      ValidationError::new(
        "\{r(instance)} is not valid under any of the given schemas",
        context=all_errors,
      ),
    )
  })
}

///|
fn kw_one_of(
  validator : Validator,
  one_of : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    let subschemas = py_iter(one_of)
    let all_errors = []
    let mut first_valid : (Int, Json)? = None
    for index, subschema in subschemas {
      let errs = validator
        .descend(instance, subschema, schema_path=Index(index))
        .to_array()
      if errs.is_empty() {
        first_valid = Some((index, subschema))
        break
      }
      all_errors.append(errs)
    }
    guard first_valid is Some((first_index, first)) else {
      return yield_(
        ValidationError::new(
          "\{r(instance)} is not valid under any of the given schemas",
          context=all_errors,
        ),
      )
    }
    let more_valid = []
    for i in (first_index + 1)..<subschemas.length() {
      let each = subschemas[i]
      if validator.evolve(schema=each).is_valid(instance) {
        more_valid.push(each)
      }
    }
    if more_valid.length() > 0 {
      more_valid.push(first)
      let reprs = more_valid.map(r).join(", ")
      return yield_(err("\{r(instance)} is valid under each of \{reprs}"))
    }
    true
  })
}

///|
fn kw_not(
  validator : Validator,
  not_schema : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.evolve(schema=not_schema).is_valid(instance) {
      return yield_(
        err("\{r(instance)} should not be valid under \{r(not_schema)}"),
      )
    }
    true
  })
}

///|
fn kw_if(
  validator : Validator,
  if_schema : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    if validator.evolve(schema=if_schema).is_valid(instance) {
      if get_key(schema, "then") is Some(then) {
        return validator
          .descend(instance, then, schema_path=Key("then"))
          .run(yield_)
      }
    } else if get_key(schema, "else") is Some(else_) {
      return validator
        .descend(instance, else_, schema_path=Key("else"))
        .run(yield_)
    }
    true
  })
}

///|
fn kw_unevaluated_items(
  validator : Validator,
  _unevaluated_items : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Array(xs) && validator.is_type(instance, "array") else {
      return true
    }
    let evaluated = find_evaluated_item_indexes_by_schema(
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
fn kw_unevaluated_properties(
  validator : Validator,
  unevaluated_properties : Json,
  instance : Json,
  schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Object(obj) && validator.is_type(instance, "object") else {
      return true
    }
    let evaluated_keys = find_evaluated_property_keys_by_schema(
      validator, instance, schema,
    )
    unevaluated_properties_errors(
      validator, unevaluated_properties, obj, evaluated_keys, yield_,
    )
  })
}

///|
/// The shared tail of the `unevaluatedProperties` implementations.
fn unevaluated_properties_errors(
  validator : Validator,
  unevaluated_properties : Json,
  obj : Map[String, Json],
  evaluated_keys : Array[String],
  yield_ : (ValidationError) -> Bool raise,
) -> Bool raise {
  let unevaluated_keys = []
  for property, value in obj {
    if !evaluated_keys.contains(property) {
      validator
      .descend(
        value,
        unevaluated_properties,
        path=Key(property),
        schema_path=Key(property),
      )
      .each(_ => unevaluated_keys.push(property))
    }
  }
  if unevaluated_keys.length() > 0 {
    if unevaluated_properties is False {
      let (extras, verb) = extras_msg(
        py_sorted(unevaluated_keys).map(k => Json::string(k)),
      )
      return yield_(
        err(
          "Unevaluated properties are not allowed (\{extras} \{verb} unexpected)",
        ),
      )
    } else {
      let (extras, verb) = extras_msg(
        unevaluated_keys.map(k => Json::string(k)),
      )
      return yield_(
        err(
          "Unevaluated properties are not valid under the given schema (\{extras} \{verb} unevaluated and invalid)",
        ),
      )
    }
  }
  true
}

///|
fn kw_prefix_items(
  validator : Validator,
  prefix_items : Json,
  instance : Json,
  _schema : Json,
) -> Errors {
  Errors::new(fn(yield_) raise {
    guard instance is Array(xs) && validator.is_type(instance, "array") else {
      return true
    }
    let subschemas = py_iter(prefix_items)
    for index, item in xs {
      if index >= subschemas.length() {
        break
      }
      let ok = validator
        .descend(
          item,
          subschemas[index],
          schema_path=Index(index),
          path=Index(index),
        )
        .run(yield_)
      if !ok {
        return false
      }
    }
    true
  })
}
