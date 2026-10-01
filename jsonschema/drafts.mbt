// The validator classes for each draft (the bottom of
// `jsonschema/validators.py`).

///|
fn meta_schema_of(uri : String) -> Json {
  match @specifications.contents(uri) {
    Some(j) => j
    None => abort("missing meta-schema \{uri}")
  }
}

///|
/// `Draft3Validator`.
pub let draft3_validator : ValidatorClass = create(
  meta_schema=meta_schema_of("http://json-schema.org/draft-03/schema#"),
  validators=[
    ("$ref", kw_ref),
    ("additionalItems", kw_additional_items),
    ("additionalProperties", kw_additional_properties),
    ("dependencies", kw_dependencies_draft3),
    ("disallow", kw_disallow_draft3),
    ("divisibleBy", kw_multiple_of),
    ("enum", kw_enum),
    ("extends", kw_extends_draft3),
    ("format", kw_format),
    ("items", kw_items_draft3_draft4),
    ("maxItems", kw_max_items),
    ("maxLength", kw_max_length),
    ("maximum", kw_maximum_draft3_draft4),
    ("minItems", kw_min_items),
    ("minLength", kw_min_length),
    ("minimum", kw_minimum_draft3_draft4),
    ("pattern", kw_pattern),
    ("patternProperties", kw_pattern_properties),
    ("properties", kw_properties_draft3),
    ("type", kw_type_draft3),
    ("uniqueItems", kw_unique_items),
  ],
  type_checker=draft3_type_checker,
  format_checker=draft3_format_checker,
  version="draft3",
  id_of=fn(j) { @referencing.draft3().id_of(j) },
  applicable_validators=ignore_ref_siblings,
)

///|
/// `Draft4Validator`.
pub let draft4_validator : ValidatorClass = create(
  meta_schema=meta_schema_of("http://json-schema.org/draft-04/schema#"),
  validators=[
    ("$ref", kw_ref),
    ("additionalItems", kw_additional_items),
    ("additionalProperties", kw_additional_properties),
    ("allOf", kw_all_of),
    ("anyOf", kw_any_of),
    ("dependencies", kw_dependencies_draft4_draft6_draft7),
    ("enum", kw_enum),
    ("format", kw_format),
    ("items", kw_items_draft3_draft4),
    ("maxItems", kw_max_items),
    ("maxLength", kw_max_length),
    ("maxProperties", kw_max_properties),
    ("maximum", kw_maximum_draft3_draft4),
    ("minItems", kw_min_items),
    ("minLength", kw_min_length),
    ("minProperties", kw_min_properties),
    ("minimum", kw_minimum_draft3_draft4),
    ("multipleOf", kw_multiple_of),
    ("not", kw_not),
    ("oneOf", kw_one_of),
    ("pattern", kw_pattern),
    ("patternProperties", kw_pattern_properties),
    ("properties", kw_properties),
    ("required", kw_required),
    ("type", kw_type),
    ("uniqueItems", kw_unique_items),
  ],
  type_checker=draft4_type_checker,
  format_checker=draft4_format_checker,
  version="draft4",
  id_of=fn(j) { @referencing.draft4().id_of(j) },
  applicable_validators=ignore_ref_siblings,
)

///|
/// `Draft6Validator`.
pub let draft6_validator : ValidatorClass = create(
  meta_schema=meta_schema_of("http://json-schema.org/draft-06/schema#"),
  validators=[
    ("$ref", kw_ref),
    ("additionalItems", kw_additional_items),
    ("additionalProperties", kw_additional_properties),
    ("allOf", kw_all_of),
    ("anyOf", kw_any_of),
    ("const", kw_const),
    ("contains", kw_contains_draft6_draft7),
    ("dependencies", kw_dependencies_draft4_draft6_draft7),
    ("enum", kw_enum),
    ("exclusiveMaximum", kw_exclusive_maximum),
    ("exclusiveMinimum", kw_exclusive_minimum),
    ("format", kw_format),
    ("items", kw_items_draft6_draft7_draft201909),
    ("maxItems", kw_max_items),
    ("maxLength", kw_max_length),
    ("maxProperties", kw_max_properties),
    ("maximum", kw_maximum),
    ("minItems", kw_min_items),
    ("minLength", kw_min_length),
    ("minProperties", kw_min_properties),
    ("minimum", kw_minimum),
    ("multipleOf", kw_multiple_of),
    ("not", kw_not),
    ("oneOf", kw_one_of),
    ("pattern", kw_pattern),
    ("patternProperties", kw_pattern_properties),
    ("properties", kw_properties),
    ("propertyNames", kw_property_names),
    ("required", kw_required),
    ("type", kw_type),
    ("uniqueItems", kw_unique_items),
  ],
  type_checker=draft6_type_checker,
  format_checker=draft6_format_checker,
  version="draft6",
  id_of=fn(j) { @referencing.draft6().id_of(j) },
  applicable_validators=ignore_ref_siblings,
)

///|
/// `Draft7Validator`.
pub let draft7_validator : ValidatorClass = create(
  meta_schema=meta_schema_of("http://json-schema.org/draft-07/schema#"),
  validators=[
    ("$ref", kw_ref),
    ("additionalItems", kw_additional_items),
    ("additionalProperties", kw_additional_properties),
    ("allOf", kw_all_of),
    ("anyOf", kw_any_of),
    ("const", kw_const),
    ("contains", kw_contains_draft6_draft7),
    ("dependencies", kw_dependencies_draft4_draft6_draft7),
    ("enum", kw_enum),
    ("exclusiveMaximum", kw_exclusive_maximum),
    ("exclusiveMinimum", kw_exclusive_minimum),
    ("format", kw_format),
    ("if", kw_if),
    ("items", kw_items_draft6_draft7_draft201909),
    ("maxItems", kw_max_items),
    ("maxLength", kw_max_length),
    ("maxProperties", kw_max_properties),
    ("maximum", kw_maximum),
    ("minItems", kw_min_items),
    ("minLength", kw_min_length),
    ("minProperties", kw_min_properties),
    ("minimum", kw_minimum),
    ("multipleOf", kw_multiple_of),
    ("not", kw_not),
    ("oneOf", kw_one_of),
    ("pattern", kw_pattern),
    ("patternProperties", kw_pattern_properties),
    ("properties", kw_properties),
    ("propertyNames", kw_property_names),
    ("required", kw_required),
    ("type", kw_type),
    ("uniqueItems", kw_unique_items),
  ],
  type_checker=draft7_type_checker,
  format_checker=draft7_format_checker,
  version="draft7",
  id_of=fn(j) { @referencing.draft7().id_of(j) },
  applicable_validators=ignore_ref_siblings,
)

///|
/// `Draft201909Validator`.
pub let draft201909_validator : ValidatorClass = create(
  meta_schema=meta_schema_of("https://json-schema.org/draft/2019-09/schema"),
  validators=[
    ("$recursiveRef", kw_recursive_ref),
    ("$ref", kw_ref),
    ("additionalItems", kw_additional_items),
    ("additionalProperties", kw_additional_properties),
    ("allOf", kw_all_of),
    ("anyOf", kw_any_of),
    ("const", kw_const),
    ("contains", kw_contains),
    ("dependentRequired", kw_dependent_required),
    ("dependentSchemas", kw_dependent_schemas),
    ("enum", kw_enum),
    ("exclusiveMaximum", kw_exclusive_maximum),
    ("exclusiveMinimum", kw_exclusive_minimum),
    ("format", kw_format),
    ("if", kw_if),
    ("items", kw_items_draft6_draft7_draft201909),
    ("maxItems", kw_max_items),
    ("maxLength", kw_max_length),
    ("maxProperties", kw_max_properties),
    ("maximum", kw_maximum),
    ("minItems", kw_min_items),
    ("minLength", kw_min_length),
    ("minProperties", kw_min_properties),
    ("minimum", kw_minimum),
    ("multipleOf", kw_multiple_of),
    ("not", kw_not),
    ("oneOf", kw_one_of),
    ("pattern", kw_pattern),
    ("patternProperties", kw_pattern_properties),
    ("properties", kw_properties),
    ("propertyNames", kw_property_names),
    ("required", kw_required),
    ("type", kw_type),
    ("unevaluatedItems", kw_unevaluated_items_draft2019),
    ("unevaluatedProperties", kw_unevaluated_properties_draft2019),
    ("uniqueItems", kw_unique_items),
  ],
  type_checker=draft201909_type_checker,
  format_checker=draft201909_format_checker,
  version="draft2019-09",
)

///|
/// `Draft202012Validator`.
pub let draft202012_validator : ValidatorClass = create(
  meta_schema=meta_schema_of("https://json-schema.org/draft/2020-12/schema"),
  validators=[
    ("$dynamicRef", kw_dynamic_ref),
    ("$ref", kw_ref),
    ("additionalProperties", kw_additional_properties),
    ("allOf", kw_all_of),
    ("anyOf", kw_any_of),
    ("const", kw_const),
    ("contains", kw_contains),
    ("dependentRequired", kw_dependent_required),
    ("dependentSchemas", kw_dependent_schemas),
    ("enum", kw_enum),
    ("exclusiveMaximum", kw_exclusive_maximum),
    ("exclusiveMinimum", kw_exclusive_minimum),
    ("format", kw_format),
    ("if", kw_if),
    ("items", kw_items),
    ("maxItems", kw_max_items),
    ("maxLength", kw_max_length),
    ("maxProperties", kw_max_properties),
    ("maximum", kw_maximum),
    ("minItems", kw_min_items),
    ("minLength", kw_min_length),
    ("minProperties", kw_min_properties),
    ("minimum", kw_minimum),
    ("multipleOf", kw_multiple_of),
    ("not", kw_not),
    ("oneOf", kw_one_of),
    ("pattern", kw_pattern),
    ("patternProperties", kw_pattern_properties),
    ("prefixItems", kw_prefix_items),
    ("properties", kw_properties),
    ("propertyNames", kw_property_names),
    ("required", kw_required),
    ("type", kw_type),
    ("unevaluatedItems", kw_unevaluated_items),
    ("unevaluatedProperties", kw_unevaluated_properties),
    ("uniqueItems", kw_unique_items),
  ],
  type_checker=draft202012_type_checker,
  format_checker=draft202012_format_checker,
  version="draft2020-12",
)

///|
let latest_cell : Ref[ValidatorClass?] = { val: None }

///|
fn init {
  // Referencing every class here makes sure each is created (and thereby
  // registered with `validates`); re-register them in upstream's order.
  let classes = [
    ("draft3", draft3_validator),
    ("draft4", draft4_validator),
    ("draft6", draft6_validator),
    ("draft7", draft7_validator),
    ("draft2019-09", draft201909_validator),
    ("draft2020-12", draft202012_validator),
  ]
  validators_by_version.clear()
  meta_schemas.clear()
  for pair in classes {
    ignore(validates(pair.1, pair.0))
  }
  latest_cell.val = Some(draft202012_validator)
}

///|
/// `_LATEST_VERSION`: the validator class used for schemas without a
/// (known) `$schema`.
pub fn latest_version() -> ValidatorClass {
  match latest_cell.val {
    Some(cls) => cls
    None => abort("validator classes are not initialized")
  }
}
