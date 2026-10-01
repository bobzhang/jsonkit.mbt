///|
/// A keyword implementation (upstream's `SchemaKeywordValidator`): given the
/// validator, the keyword's value, the instance and the (sub)schema
/// containing the keyword, the (lazy) errors.
pub type KeywordFn = (Validator, Json, Json, Json) -> Errors

///|
/// Which keywords of a schema apply (upstream's `applicable_validators`).
pub type ApplicableValidators = (Json) -> Array[(String, Json)]

///|
/// A validator class (upstream: the class returned by `create`, e.g.
/// `Draft202012Validator`): the keyword implementations, meta-schema, type
/// checker and format checker of a JSON Schema dialect.
///
/// Create validators for a schema with `ValidatorClass::new`.
pub struct ValidatorClass {
  /// The class name, e.g. `Draft7Validator`.
  name : String
  /// `VALIDATORS`: keyword name to implementation, in definition order.
  validators : Map[String, KeywordFn]
  /// `META_SCHEMA`
  meta_schema : Json
  /// `TYPE_CHECKER`
  type_checker : TypeChecker
  /// `FORMAT_CHECKER`: the checker to use when format validation is wanted
  /// (validators only check formats when given a `format_checker`).
  format_checker : FormatChecker
  /// `ID_OF`
  id_of : (Json) -> String?
  /// `_APPLICABLE_VALIDATORS`
  applicable_validators : ApplicableValidators
  priv specification : @referencing.Specification
}

///|
pub impl Show for ValidatorClass with output(self, logger) {
  logger.write_string("<class 'jsonschema.validators.\{self.name}'>")
}

///|
/// A validator for a particular schema (an instance of a validator class).
pub struct Validator {
  /// The validator class.
  cls : ValidatorClass
  /// The schema being validated against.
  schema : Json
  /// The format checker in use, if any (format validation is off without
  /// one).
  format_checker : FormatChecker?
  priv registry : @referencing.Registry?
  priv resolver : @referencing.Resolver
  priv validators : Array[(KeywordFn, String, Json)]
}

///|
/// `repr(validator)`: e.g. `Draft7Validator(schema={'type': 'string'},
/// format_checker=None)` (the schema is abbreviated like `reprlib.repr`).
pub impl Show for Validator with output(self, logger) {
  let fc = match self.format_checker {
    Some(fc) => fc.to_string()
    None => "None"
  }
  logger.write_string(
    "\{self.cls.name}(schema=\{@pycompat.short_repr(self.schema)}, format_checker=\{fc})",
  )
}

///|
/// `jsonschema_specifications.REGISTRY`: all meta-schemas and vocabularies.
pub fn specifications_registry() -> @referencing.Registry {
  match specifications_cache.val {
    Some(r) => r
    None => {
      let resources = @specifications.schemas().map(pair => {
        @referencing.Resource::from_contents(pair.1) catch {
          e => abort("cannot load \{pair.0}: \{e}")
        }
      })
      let registry = @referencing.Registry::new().with_identified_resources(
        resources,
      ) catch {
        e => abort("cannot load the specifications: \{e}")
      }
      let registry = registry.crawl() catch {
        e => abort("cannot crawl the specifications: \{e}")
      }
      specifications_cache.val = Some(registry)
      registry
    }
  }
}

///|
let specifications_cache : Ref[@referencing.Registry?] = { val: None }

///|
/// `_VALIDATORS`: version name to validator class.
let validators_by_version : Map[String, ValidatorClass] = Map([])

///|
/// `_META_SCHEMAS`: normalized meta-schema id to validator class.
let meta_schemas : Map[String, ValidatorClass] = Map([])

///|
/// `URIDict.normalize`: `urlsplit(uri).geturl()`.
fn normalize_uri(uri : String) -> String {
  @urllib.urlsplit(uri).geturl() catch {
    _ => uri
  }
}

///|
/// Register a validator class for a `version` of the specification
/// (upstream's `validates` decorator): it is then considered when looking
/// up `$schema` URIs.
pub fn validates(cls : ValidatorClass, version : String) -> ValidatorClass {
  validators_by_version[version] = cls
  match (cls.id_of)(cls.meta_schema) {
    Some(id) => meta_schemas[normalize_uri(id)] = cls
    None => meta_schemas[normalize_uri("")] = cls
  }
  cls
}

///|
/// The registered validator classes (upstream's `_VALIDATORS`), keyed by
/// version name.
pub fn registered_validators() -> Map[String, ValidatorClass] {
  validators_by_version.copy()
}

///|
fn default_applicable(schema : Json) -> Array[(String, Json)] {
  match schema {
    Object(m) => m.iter().collect()
    _ => []
  }
}

///|
/// Create a new validator class (upstream's `create`).
///
/// `validators` maps keyword names to their implementations. When a
/// `version` is given, the class is named after it (`version.title()` minus
/// spaces and dashes, plus `Validator`) and registered with `validates`.
pub fn create(
  meta_schema~ : Json,
  validators? : ArrayView[(String, KeywordFn)] = [],
  version? : String,
  type_checker? : TypeChecker = draft202012_type_checker,
  format_checker? : FormatChecker = draft202012_format_checker,
  id_of? : (Json) -> String? = fn(j) { @referencing.draft202012().id_of(j) },
  applicable_validators? : ApplicableValidators = default_applicable,
) -> ValidatorClass {
  let dialect_id = id_of(meta_schema).unwrap_or("urn:unknown-dialect")
  let specification = @referencing.specification_with(
    dialect_id,
    default=@referencing.opaque_specification,
  ) catch {
    _ => @referencing.opaque_specification
  }
  let keyword_map = Map([])
  for pair in validators {
    keyword_map[pair.0] = pair.1
  }
  let name = match version {
    Some(v) => title_case(v).replace_all(old=" ", new="").replace_all(old="-", new="") + "Validator"
    None => "Validator"
  }
  let cls = {
    name,
    validators: keyword_map,
    meta_schema,
    type_checker,
    format_checker,
    id_of,
    applicable_validators,
    specification,
  }
  match version {
    Some(v) => validates(cls, v)
    None => cls
  }
}

///|
/// Python's `str.title()` for ASCII text.
fn title_case(s : String) -> String {
  let sb = StringBuilder()
  let mut prev_letter = false
  for c in s {
    let is_letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    if is_letter {
      if prev_letter {
        sb.write_char(if c >= 'A' && c <= 'Z' { Int::unsafe_to_char(c.to_int() + 32) } else { c })
      } else {
        sb.write_char(if c >= 'a' && c <= 'z' { Int::unsafe_to_char(c.to_int() - 32) } else { c })
      }
    } else {
      sb.write_char(c)
    }
    prev_letter = is_letter
  }
  sb.to_string()
}

///|
/// Create a new validator class by extending an existing one (upstream's
/// `extend`). Keyword implementations in `validators` replace any existing
/// ones with the same name.
pub fn extend(
  cls : ValidatorClass,
  validators? : ArrayView[(String, KeywordFn)] = [],
  version? : String,
  type_checker? : TypeChecker,
  format_checker? : FormatChecker,
) -> ValidatorClass {
  let all = cls.validators.iter().collect()
  for pair in validators {
    match all.search_by(p => p.0 == pair.0) {
      Some(i) => all[i] = pair
      None => all.push(pair)
    }
  }
  create(
    meta_schema=cls.meta_schema,
    validators=all,
    version?,
    type_checker=type_checker.unwrap_or(cls.type_checker),
    format_checker=format_checker.unwrap_or(cls.format_checker),
    id_of=cls.id_of,
    applicable_validators=cls.applicable_validators,
  )
}

///|
/// Retrieve the validator class appropriate for validating the given
/// schema, from its `$schema` keyword (upstream's `validator_for`).
///
/// Schemas without (a known) `$schema` get `default`, or the latest
/// supported draft.
pub fn validator_for(
  schema : Json,
  default? : ValidatorClass,
) -> ValidatorClass {
  let default_validator = match default {
    Some(d) => d
    None => latest_version()
  }
  match schema {
    Object({ "$schema": String(dialect), .. }) =>
      match meta_schemas.get(normalize_uri(dialect)) {
        Some(cls) => cls
        None => default_validator
      }
    _ => default_validator
  }
}

///|
/// Validate `schema` against its class's meta-schema (upstream's
/// `check_schema`), raising `SchemaError` for the first problem found.
///
/// Format validation of the schema uses the meta-schema's validator class's
/// `FORMAT_CHECKER` unless `format_checker` is given.
pub fn ValidatorClass::check_schema(
  self : ValidatorClass,
  schema : Json,
  format_checker? : FormatChecker?,
) -> Unit raise {
  let validator_cls = validator_for(self.meta_schema, default=self)
  let format_checker = match format_checker {
    Some(fc) => fc
    None => Some(validator_cls.format_checker)
  }
  let validator = validator_cls.new(self.meta_schema, format_checker?)
  match validator.iter_errors(schema).first() {
    Some(error) => raise SchemaError(ValidationError::create_from(error))
    None => ()
  }
}

///|
/// Create a validator for `schema` (upstream: calling the class).
///
/// `registry` holds the resources `$ref`s may refer to (it is combined with
/// `specifications_registry()`); `format_checker` enables format
/// validation.
pub fn ValidatorClass::new(
  self : ValidatorClass,
  schema : Json,
  format_checker? : FormatChecker,
  registry? : @referencing.Registry,
) -> Validator raise {
  let combined = match registry {
    None => specifications_registry()
    Some(r) => specifications_registry().combine([r])
  }
  if (schema is True || schema is False) &&
    (self.specification.name == "draft-03" ||
    self.specification.name == "draft-04") {
    // `referencing.jsonschema._legacy_id` does `"$ref" in contents`.
    raise PythonError("TypeError: argument of type 'bool' is not iterable")
  }
  let resource = self.specification.create_resource(schema)
  let resolver = combined.resolver_with_root(resource)
  Validator::make(self, schema, format_checker, registry, resolver)
}

///|
fn Validator::make(
  cls : ValidatorClass,
  schema : Json,
  format_checker : FormatChecker?,
  registry : @referencing.Registry?,
  resolver : @referencing.Resolver,
) -> Validator {
  let validators = match schema {
    True | False => []
    _ =>
      (cls.applicable_validators)(schema)
      .filter_map(pair => match cls.validators.get(pair.0) {
        Some(f) => Some((f, pair.0, pair.1))
        None => None
      })
  }
  { cls, schema, format_checker, registry, resolver, validators }
}

///|
/// A copy of this validator with some attributes changed (upstream's
/// `evolve`). When the schema changes, the validator class is re-selected
/// with `validator_for(schema, default=self.cls)`.
pub fn Validator::evolve(
  self : Validator,
  schema? : Json,
  format_checker? : FormatChecker?,
  resolver? : @referencing.Resolver,
) -> Validator {
  let schema = schema.unwrap_or(self.schema)
  let cls = validator_for(schema, default=self.cls)
  let format_checker = match format_checker {
    Some(fc) => fc
    None => self.format_checker
  }
  Validator::make(
    cls,
    schema,
    format_checker,
    self.registry,
    resolver.unwrap_or(self.resolver),
  )
}

///|
/// The resolver used for `$ref`s in the current schema.
pub fn Validator::resolver(self : Validator) -> @referencing.Resolver {
  self.resolver
}

///|
fn false_schema_error(
  instance : Json,
  schema : Json,
  path? : PathItem,
  schema_path? : PathItem,
) -> ValidationError {
  ValidationError::new(
    "False schema does not allow \{@pycompat.repr(instance)}",
    validator=Json::null(),
    validator_value=Json::null(),
    instance~,
    schema~,
    path=match path {
      Some(p) => [p]
      None => []
    },
    schema_path=match schema_path {
      Some(p) => [p]
      None => []
    },
  )
}

///|
/// Lazily yield each of the errors in the given instance (upstream's
/// `iter_errors`).
pub fn Validator::iter_errors(self : Validator, instance : Json) -> Errors {
  let schema = self.schema
  Errors::new(fn(yield_) {
    match schema {
      True => return true
      False => return yield_(false_schema_error(instance, schema))
      _ => ()
    }
    for entry in self.validators {
      let (f, k, v) = entry
      let ok = f(self, v, instance, schema).run(fn(error) {
        error.set_unset(
          validator=Json::string(k),
          validator_value=v,
          instance~,
          schema~,
          type_checker=self.cls.type_checker,
        )
        if k != "if" && k != "$ref" {
          error.schema_path.insert(0, Key(k))
        }
        yield_(error)
      })
      if !ok {
        return false
      }
    }
    true
  })
}

///|
/// Validate `instance` against a subschema, prefixing the errors' paths
/// (upstream's `descend`).
pub fn Validator::descend(
  self : Validator,
  instance : Json,
  schema : Json,
  path? : PathItem,
  schema_path? : PathItem,
  resolver? : @referencing.Resolver,
) -> Errors {
  Errors::new(fn(yield_) {
    match schema {
      True => return true
      False =>
        return yield_(
          false_schema_error(instance, schema, path?, schema_path?),
        )
      _ => ()
    }
    let resolver = match resolver {
      Some(r) => r
      None =>
        self.resolver.in_subresource(
          self.cls.specification.create_resource(schema),
        )
    }
    let evolved = self.evolve(schema~, resolver~)
    for pair in (self.cls.applicable_validators)(schema) {
      let (k, v) = pair
      guard evolved.cls.validators.get(k) is Some(f) else { continue }
      let ok = f(evolved, v, instance, schema).run(fn(error) {
        error.set_unset(
          validator=Json::string(k),
          validator_value=v,
          instance~,
          schema~,
          type_checker=evolved.cls.type_checker,
        )
        if k != "if" && k != "$ref" {
          error.schema_path.insert(0, Key(k))
        }
        if path is Some(p) {
          error.path.insert(0, p)
        }
        if schema_path is Some(p) {
          error.schema_path.insert(0, p)
        }
        yield_(error)
      })
      if !ok {
        return false
      }
    }
    true
  })
}

///|
/// Check if the instance is valid under the current schema, raising the
/// first error otherwise (upstream's `validate` method).
pub fn Validator::validate(self : Validator, instance : Json) -> Unit raise {
  match self.iter_errors(instance).first() {
    Some(error) => raise ValidationError(error)
    None => ()
  }
}

///|
/// Check if the instance is of the given (JSON Schema) type, raising
/// `UnknownType` for types the type checker does not know.
pub fn Validator::is_type(
  self : Validator,
  instance : Json,
  type_ : String,
) -> Bool raise {
  self.cls.type_checker.is_type(instance, type_) catch {
    UndefinedTypeCheck(_) =>
      raise UnknownType(type_=Json::string(type_), instance~, schema=self.schema)
    e => raise e
  }
}

///|
/// Whether the instance is valid under the current schema (stops at the
/// first error).
pub fn Validator::is_valid(self : Validator, instance : Json) -> Bool raise {
  self.iter_errors(instance).is_empty()
}

///|
/// Upstream's `_validate_reference`: look `ref` up and validate against
/// what it points to.
fn Validator::validate_reference(
  self : Validator,
  ref_ : String,
  instance : Json,
) -> Errors raise {
  let resolved = self.resolver.lookup(ref_)
  self.descend(instance, resolved.contents, resolver=resolved.resolver)
}

///|
/// Validate an instance under the given schema (upstream's
/// `jsonschema.validate`): the schema is checked first (raising
/// `SchemaError`), then the best match among the instance's errors is
/// raised as a `ValidationError`.
///
/// Without `cls`, the validator class is chosen from the schema's
/// `$schema` (see `validator_for`).
pub fn validate(
  instance : Json,
  schema : Json,
  cls? : ValidatorClass,
  format_checker? : FormatChecker,
  registry? : @referencing.Registry,
) -> Unit raise {
  let cls = match cls {
    Some(c) => c
    None => validator_for(schema)
  }
  cls.check_schema(schema)
  let validator = cls.new(schema, format_checker?, registry?)
  let errors = validator.iter_errors(instance).to_array()
  match best_match(errors.iter()) {
    Some(error) => raise ValidationError(error)
    None => ()
  }
}
