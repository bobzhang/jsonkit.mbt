// Port of jmespath/functions.py.
//
// Upstream registers builtin functions with a metaclass: every method named
// `_func_<name>` decorated with `@signature(...)` lands in `FUNCTION_TABLE`,
// and custom functions are added by subclassing `Functions`.  Here a
// `Functions` value owns a mutable table of `FunctionSpec`s; `Functions::new`
// starts from the builtins and `Functions::register_function` adds (or
// overrides) entries.

///|
/// One entry of a function signature (`{'types': [...], 'variadic': ...}`).
///
/// `types` are JMESPath type names: `number`, `string`, `boolean`, `array`,
/// `object`, `null`, `expref`, or typed arrays such as `array-number`.  An
/// empty list accepts any value.
pub(all) struct ArgSpec {
  types : Array[String]
  variadic : Bool
} derive(Eq, Debug)

///|
pub fn ArgSpec::new(types : Array[String], variadic? : Bool = false) -> ArgSpec {
  { types, variadic }
}

///|
/// The implementation of a JMESPath function.  Arguments have already been
/// validated against the signature.
pub type FunctionImpl = (Array[Value]) -> Json raise JMESPathError

///|
/// A function table entry (`{'function': ..., 'signature': ...}`).
pub(all) struct FunctionSpec {
  function : FunctionImpl
  signature : Array[ArgSpec]
}

///|
/// A table of JMESPath functions (`jmespath.functions.Functions`).
pub struct Functions {
  priv function_table : Map[String, FunctionSpec]
}

///|
/// A function table with all the builtin functions.
pub fn Functions::new() -> Functions {
  { function_table: builtin_function_table() }
}

///|
/// Adds a function to the table, replacing any function with the same name
/// (upstream: define `_func_<name>` with `@signature(...)` in a subclass).
///
/// ```mbt check
/// test {
///   let functions = @jmespath.Functions::new()
///   functions.register_function(
///     "double",
///     [@jmespath.ArgSpec::new(["number"])],
///     args => {
///       guard args[0] is Data(Number(n, ..)) else { Json::null() }
///       Json::number(n * 2.0)
///     },
///   )
///   let options = @jmespath.Options::new(custom_functions=functions)
///   let result = @jmespath.search("double(`21`)", Json::null(), options~)
///   json_inspect(result, content=42)
/// }
/// ```
pub fn Functions::register_function(
  self : Functions,
  name : String,
  signature : Array[ArgSpec],
  function : FunctionImpl,
) -> Unit {
  self.function_table[name] = { function, signature }
}

///|
/// Looks up a function by name.
pub fn Functions::get(self : Functions, name : String) -> FunctionSpec? {
  self.function_table.get(name)
}

///|
/// The names of all functions in the table.
pub fn Functions::names(self : Functions) -> Array[String] {
  self.function_table.keys().collect()
}

///|
/// Validates `resolved_args` against the function's signature and calls it.
pub fn Functions::call_function(
  self : Functions,
  function_name : String,
  resolved_args : Array[Value],
) -> Json raise JMESPathError {
  guard self.function_table.get(function_name) is Some(spec) else {
    raise UnknownFunctionError("Unknown function: \{function_name}()")
  }
  validate_arguments(resolved_args, spec.signature, function_name)
  (spec.function)(resolved_args)
}

///|
/// The table used when `Options` has no custom functions.
let default_functions : Functions = Functions::new()

// ---------------------------------------------------------------------------
// Type checking

///|
/// `REVERSE_TYPES_MAP`: JMESPath type -> Python type names.
fn reverse_types_map(t : String) -> Array[String] {
  match t {
    "boolean" => ["bool"]
    "array" => ["list", "_Projection"]
    "object" => ["dict", "OrderedDict"]
    "null" => ["NoneType"]
    "string" => ["unicode", "str"]
    "number" => ["float", "int", "long"]
    "expref" => ["_Expression"]
    _ => []
  }
}

///|
/// `TYPES_MAP.get(pyobject, 'unknown')`: Python type name -> JMESPath type.
fn convert_to_jmespath_type(pyobject : String) -> String {
  match pyobject {
    "bool" => "boolean"
    "list" | "_Projection" => "array"
    "dict" | "OrderedDict" => "object"
    "NoneType" => "null"
    "unicode" | "str" => "string"
    "float" | "int" | "long" => "number"
    "_Expression" => "expref"
    _ => "unknown"
  }
}

///|
fn validate_arguments(
  args : Array[Value],
  signature : Array[ArgSpec],
  function_name : String,
) -> Unit raise JMESPathError {
  if signature.last() is Some(last) && last.variadic {
    if args.length() < signature.length() {
      raise VariadictArityError(
        expected_arity=signature.length(),
        actual_arity=args.length(),
        function_name~,
      )
    }
  } else if args.length() != signature.length() {
    raise ArityError(
      expected_arity=signature.length(),
      actual_arity=args.length(),
      function_name~,
    )
  }
  type_check(args, signature, function_name)
}

///|
fn type_check(
  actual : Array[Value],
  signature : Array[ArgSpec],
  function_name : String,
) -> Unit raise JMESPathError {
  for i in 0..<signature.length() {
    let allowed_types = signature[i].types
    if !allowed_types.is_empty() {
      type_check_single(actual[i], allowed_types, function_name)
    }
  }
}

///|
fn type_check_single(
  current : Value,
  types : Array[String],
  function_name : String,
) -> Unit raise JMESPathError {
  // Type checking involves checking the top level type, and in the case of
  // arrays, potentially checking the types of each element.
  let (allowed_types, allowed_subtypes) = get_allowed_pytypes(types)
  // Upstream deliberately uses type(current).__name__ rather than
  // isinstance(): booleans are not numbers.
  let actual_typename = current.py_type_name()
  if !allowed_types.contains(actual_typename) {
    raise JMESPathTypeError(
      function_name~,
      current_value=current,
      actual_type=convert_to_jmespath_type(actual_typename),
      expected_types=types,
    )
  }
  // If we're dealing with a list type, we can have additional restrictions
  // on the type of the list elements.  Arrays are the only types that can
  // have subtypes.
  if !allowed_subtypes.is_empty() {
    subtype_check(current, allowed_subtypes, types, function_name)
  }
}

///|
fn get_allowed_pytypes(
  types : Array[String],
) -> (Array[String], Array[Array[String]]) {
  let allowed_types = []
  let allowed_subtypes = []
  for t in types {
    let type_ = match t.find("-") {
      Some(i) => {
        let subtype = t.view(start_offset=i + 1).to_owned()
        allowed_subtypes.push(reverse_types_map(subtype))
        t.view(end_offset=i).to_owned()
      }
      None => t
    }
    allowed_types.append(reverse_types_map(type_))
  }
  (allowed_types, allowed_subtypes)
}

///|
fn subtype_check(
  current : Value,
  allowed_subtypes : Array[Array[String]],
  types : Array[String],
  function_name : String,
) -> Unit raise JMESPathError {
  let elements = match current {
    Data(Array(items)) => items
    _ => []
  }
  if allowed_subtypes.length() == 1 {
    // The easy case, we know up front what type we need to validate.
    let allowed = allowed_subtypes[0]
    for element in elements {
      let actual_typename = py_type_name(element)
      if !allowed.contains(actual_typename) {
        // Note: upstream reports the *Python* type name here.
        raise JMESPathTypeError(
          function_name~,
          current_value=Data(element),
          actual_type=actual_typename,
          expected_types=types,
        )
      }
    }
  } else if allowed_subtypes.length() > 1 && !elements.is_empty() {
    // Dynamic type validation.  Based on the first type we see, we validate
    // that the remaining types match.
    let first = py_type_name(elements[0])
    let mut allowed = None
    for subtypes in allowed_subtypes {
      if subtypes.contains(first) {
        allowed = Some(subtypes)
        break
      }
    }
    guard allowed is Some(allowed) else {
      raise JMESPathTypeError(
        function_name~,
        current_value=Data(elements[0]),
        actual_type=first,
        expected_types=types,
      )
    }
    for element in elements {
      let actual_typename = py_type_name(element)
      if !allowed.contains(actual_typename) {
        raise JMESPathTypeError(
          function_name~,
          current_value=Data(element),
          actual_type=actual_typename,
          expected_types=types,
        )
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers

///|
/// The JSON value of a validated argument.
fn arg_data(arg : Value) -> Json {
  match arg {
    Data(v) => v
    Expref(_) => Json::null()
  }
}

///|
fn arg_array(arg : Value) -> Array[Json] {
  match arg {
    Data(Array(items)) => items
    _ => []
  }
}

///|
fn arg_object(arg : Value) -> Map[String, Json] {
  match arg {
    Data(Object(map)) => map
    _ => Map([])
  }
}

///|
fn arg_string(arg : Value) -> String {
  match arg {
    Data(String(s)) => s
    _ => ""
  }
}

///|
fn arg_expref(arg : Value) -> Expression {
  match arg {
    Expref(e) => e
    Data(_) => abort("expected an expression reference")
  }
}

///|
/// Upstream can return an `_Expression` object from functions such as
/// `not_null` or `to_array`; JSON values cannot hold one.
fn expref_as_value_error(function_name : String) -> JMESPathError {
  TypeError(
    "expression references can only be used as function arguments (in \{function_name}())",
  )
}

///|
/// Python's `sum()` of numbers: exact while all items are ints, then
/// Neumaier-compensated float summation (CPython >= 3.12).
fn py_sum(items : Array[Json]) -> Json {
  let mut i_result = 0.0
  let mut idx = 0
  while idx < items.length() {
    guard items[idx] is Number(d, repr~) else { break }
    if number_is_float(d, repr) {
      break
    }
    i_result += d
    idx += 1
  }
  if idx == items.length() {
    return make_int(i_result)
  }
  let mut f_result = i_result
  let mut c = 0.0
  for item in items[idx:] {
    guard item is Number(x, repr~) else { continue }
    if number_is_float(x, repr) {
      let t = f_result + x
      if f_result.abs() >= x.abs() {
        c += f_result - t + x
      } else {
        c += x - t + f_result
      }
      f_result = t
    } else {
      f_result += x
    }
  }
  if c != 0.0 && !c.is_nan() && !c.is_inf() {
    f_result += c
  }
  make_float(f_result)
}

///|
/// Python's `sorted()` (a stable sort that only uses `<`).
fn py_sorted(
  items : Array[Json],
  lt : (Json, Json) -> Bool raise JMESPathError,
) -> Array[Json] raise JMESPathError {
  let n = items.length()
  if n <= 1 {
    return items.copy()
  }
  let mid = n / 2
  let left = py_sorted(items[:mid].to_owned(), lt)
  let right = py_sorted(items[mid:].to_owned(), lt)
  let result = []
  let mut i = 0
  let mut j = 0
  while i < left.length() && j < right.length() {
    // Take from the right only when strictly smaller: keeps stability.
    if lt(right[j], left[i]) {
      result.push(right[j])
      j += 1
    } else {
      result.push(left[i])
      i += 1
    }
  }
  for x in left[i:] {
    result.push(x)
  }
  for x in right[j:] {
    result.push(x)
  }
  result
}

///|
/// `sorted(array, key=keyfunc)`: keys are computed first, in order.
fn py_sorted_by_key(
  items : Array[Json],
  keyfunc : (Json) -> Json raise JMESPathError,
) -> Array[Json] raise JMESPathError {
  let keyed = []
  for i, item in items {
    keyed.push(Json::array([keyfunc(item), Json::number(i.to_double())]))
  }
  let sorted = py_sorted(keyed, (a, b) => {
    guard a is Array(a) && b is Array(b) else { false }
    py_order("<", a[0], b[0])
  })
  sorted.map(pair => {
    guard pair is Array(pair) && pair[1] is Number(i, ..) else { Json::null() }
    items[i.to_int()]
  })
}

///|
fn create_key_func(
  expref : Expression,
  allowed_types : Array[String],
  function_name : String,
) -> (Json) -> Json raise JMESPathError {
  x => {
    let result = expref.visit(x)
    let jmespath_type = convert_to_jmespath_type(py_type_name(result))
    // allowed_types is in term of jmespath types, not python types.
    if !allowed_types.contains(jmespath_type) {
      raise JMESPathTypeError(
        function_name~,
        current_value=Data(result),
        actual_type=jmespath_type,
        expected_types=allowed_types,
      )
    }
    result
  }
}

///|
/// `min(array, key=keyfunc)` / `max(...)`: keys are computed lazily and
/// compared as they come, like CPython's `min_max`.
fn py_min_max_by(
  items : Array[Json],
  keyfunc : (Json) -> Json raise JMESPathError,
  op : String,
) -> Json raise JMESPathError {
  guard items.length() > 0 else { Json::null() }
  let mut best = items[0]
  let mut best_key = keyfunc(items[0])
  for item in items[1:] {
    let key = keyfunc(item)
    if py_order(op, key, best_key) {
      best = item
      best_key = key
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Builtin functions

///|
fn func_abs(args : Array[Value]) -> Json {
  guard arg_data(args[0]) is Number(d, repr~) else { Json::null() }
  if number_is_float(d, repr) {
    make_float(d.abs())
  } else {
    match repr {
      Some(r) if r.has_prefix("-") =>
        Json::number(d.abs(), repr=r.view(start_offset=1).to_owned())
      _ => Json::number(d.abs(), repr?)
    }
  }
}

///|
fn func_avg(args : Array[Value]) -> Json {
  let arg = arg_array(args[0])
  if arg.is_empty() {
    return Json::null()
  }
  guard py_sum(arg) is Number(total, ..) else { Json::null() }
  make_float(total / arg.length().to_double())
}

///|
fn func_not_null(args : Array[Value]) -> Json raise JMESPathError {
  for argument in args {
    match argument {
      Data(Null) => continue
      Data(v) => return v
      Expref(_) => raise expref_as_value_error("not_null")
    }
  }
  Json::null()
}

///|
fn func_to_array(args : Array[Value]) -> Json raise JMESPathError {
  match args[0] {
    Data(Array(_) as arr) => arr
    Data(v) => Json::array([v])
    Expref(_) => raise expref_as_value_error("to_array")
  }
}

///|
fn func_to_string(args : Array[Value]) -> Json {
  match args[0] {
    Data(String(_) as s) => s
    Data(v) => Json::string(dumps(v))
    // json.dumps(..., default=str) of the expression object.
    Expref(_) => Json::string("\"<jmespath.visitor._Expression object>\"")
  }
}

///|
fn func_to_number(args : Array[Value]) -> Json raise JMESPathError {
  match args[0] {
    Data(Array(_) | Object(_) | True | False | Null) => Json::null()
    Data(Number(_, ..) as n) => n
    Data(String(s)) =>
      match py_int_parse(s) {
        Some(v) => v
        None =>
          match py_float_parse(s) {
            Some(v) => v
            None => Json::null()
          }
      }
    Expref(_) =>
      raise TypeError(
        "int() argument must be a string, a bytes-like object or a real number, not '_Expression'",
      )
  }
}

///|
fn func_contains(args : Array[Value]) -> Json raise JMESPathError {
  let search = args[1]
  match args[0] {
    Data(Array(items)) =>
      match search {
        Data(v) => Json::boolean(items.iter().any(item => py_eq(item, v)))
        Expref(_) => Json::boolean(false)
      }
    Data(String(subject)) =>
      match search {
        Data(String(s)) => Json::boolean(subject.contains(s))
        other =>
          raise TypeError(
            "'in <string>' requires string as left operand, not \{other.py_type_name()}",
          )
      }
    _ => Json::boolean(false)
  }
}

///|
fn func_length(args : Array[Value]) -> Json {
  let n = match arg_data(args[0]) {
    // Python counts code points.
    String(s) => s.char_length()
    Array(items) => items.length()
    Object(map) => map.length()
    _ => 0
  }
  Json::number(n.to_double())
}

///|
fn func_ends_with(args : Array[Value]) -> Json {
  Json::boolean(arg_string(args[0]).has_suffix(arg_string(args[1])))
}

///|
fn func_starts_with(args : Array[Value]) -> Json {
  Json::boolean(arg_string(args[0]).has_prefix(arg_string(args[1])))
}

///|
fn func_reverse(args : Array[Value]) -> Json {
  match arg_data(args[0]) {
    // arg[::-1] reverses code points.
    String(s) => Json::string(String::from_array(s.to_array().rev()))
    Array(items) => Json::array(items.rev())
    other => other
  }
}

///|
fn func_ceil_floor(
  args : Array[Value],
  op : (Double) -> Double,
) -> Json raise JMESPathError {
  let arg = arg_data(args[0])
  guard arg is Number(d, repr~) else { Json::null() }
  if !number_is_float(d, repr) {
    return arg
  }
  if d.is_nan() {
    raise ValueError("cannot convert float NaN to integer")
  }
  if d.is_inf() {
    raise OverflowError("cannot convert float infinity to integer")
  }
  make_int(op(d))
}

///|
fn func_join(args : Array[Value]) -> Json {
  let separator = arg_string(args[0])
  let parts = arg_array(args[1]).map(item => match item {
    String(s) => s
    _ => ""
  })
  Json::string(parts.join(separator))
}

///|
fn func_map(args : Array[Value]) -> Json raise JMESPathError {
  let expref = arg_expref(args[0])
  let result = []
  for element in arg_array(args[1]) {
    result.push(expref.visit(element))
  }
  Json::array(result)
}

///|
fn func_min_max(args : Array[Value], op : String) -> Json raise JMESPathError {
  let arg = arg_array(args[0])
  guard arg.length() > 0 else { Json::null() }
  let mut best = arg[0]
  for item in arg[1:] {
    if py_order(op, item, best) {
      best = item
    }
  }
  best
}

///|
/// Python's `dict.update(other)` for a JSON value `other`.  Only the first
/// argument of `merge` is type checked upstream, so later arguments go
/// through `dict.update`'s sequence-of-pairs protocol.
fn py_dict_update(
  merged : Map[String, Json],
  other : Value,
) -> Unit raise JMESPathError {
  let items : Array[Json] = match other {
    Data(Object(map)) => {
      for k, v in map {
        merged[k] = v
      }
      return
    }
    Data(Array(items)) => items
    Data(String(s)) => s.iter().map(c => Json::string(c.to_string())).collect()
    other =>
      raise TypeError("'\{other.py_type_name()}' object is not iterable")
  }
  for i, element in items {
    let pair : Array[Json] = match element {
      Array(pair) => pair
      String(s) => s.iter().map(c => Json::string(c.to_string())).collect()
      Object(map) => map.keys().map(Json::string).collect()
      _ =>
        raise TypeError(
          "cannot convert dictionary update sequence element #\{i} to a sequence",
        )
    }
    if pair.length() != 2 {
      raise ValueError(
        "dictionary update sequence element #\{i} has length \{pair.length()}; 2 is required",
      )
    }
    match pair[0] {
      String(key) => merged[key] = pair[1]
      Array(_) | Object(_) =>
        raise TypeError("unhashable type: '\{py_type_name(pair[0])}'")
      // Python would create a non-string key, which JSON cannot hold.
      key =>
        raise TypeError(
          "dictionary key \{py_repr(key)} is not a string and cannot be represented in JSON",
        )
    }
  }
}

///|
fn func_merge(args : Array[Value]) -> Json raise JMESPathError {
  let merged : Map[String, Json] = Map([])
  for arg in args {
    py_dict_update(merged, arg)
  }
  Json::object(merged)
}

///|
fn func_sort(args : Array[Value]) -> Json raise JMESPathError {
  Json::array(py_sorted(arg_array(args[0]), (a, b) => py_order("<", a, b)))
}

///|
fn func_sum(args : Array[Value]) -> Json {
  py_sum(arg_array(args[0]))
}

///|
fn func_keys(args : Array[Value]) -> Json {
  Json::array(arg_object(args[0]).keys().map(Json::string).collect())
}

///|
fn func_values(args : Array[Value]) -> Json {
  Json::array(arg_object(args[0]).values().collect())
}

///|
fn func_type(args : Array[Value]) -> Json {
  match args[0] {
    Data(String(_)) => Json::string("string")
    Data(True | False) => Json::string("boolean")
    Data(Array(_)) => Json::string("array")
    Data(Object(_)) => Json::string("object")
    Data(Number(_, ..)) => Json::string("number")
    Data(Null) => Json::string("null")
    // Upstream falls through every isinstance() check and returns None.
    Expref(_) => Json::null()
  }
}

///|
fn func_sort_by(args : Array[Value]) -> Json raise JMESPathError {
  let array = arg_data(args[0])
  let items = arg_array(args[0])
  let expref = arg_expref(args[1])
  if items.is_empty() {
    return array
  }
  // sort_by allows for the expref to be either a number or a string, so we
  // have some special logic to handle this.  We evaluate the first array
  // element and verify that it's either a string or a number.  We then
  // create a key function that validates that type, which requires that
  // remaining array elements resolve to the same type as the first element.
  let required_type = convert_to_jmespath_type(
    py_type_name(expref.visit(items[0])),
  )
  if !(required_type is ("number" | "string")) {
    raise JMESPathTypeError(
      function_name="sort_by",
      current_value=Data(items[0]),
      actual_type=required_type,
      expected_types=["string", "number"],
    )
  }
  let keyfunc = create_key_func(expref, [required_type], "sort_by")
  Json::array(py_sorted_by_key(items, keyfunc))
}

///|
fn func_min_by(args : Array[Value]) -> Json raise JMESPathError {
  let keyfunc = create_key_func(
    arg_expref(args[1]),
    ["number", "string"],
    "min_by",
  )
  py_min_max_by(arg_array(args[0]), keyfunc, "<")
}

///|
fn func_max_by(args : Array[Value]) -> Json raise JMESPathError {
  let keyfunc = create_key_func(
    arg_expref(args[1]),
    ["number", "string"],
    "max_by",
  )
  py_min_max_by(arg_array(args[0]), keyfunc, ">")
}

///|
fn builtin_function_table() -> Map[String, FunctionSpec] {
  let any = ArgSpec::new([])
  let t = (types : Array[String]) => ArgSpec::new(types)
  let table : Map[String, FunctionSpec] = Map([])
  let def = (name : String, signature : Array[ArgSpec], function : FunctionImpl) => {
    table[name] = { function, signature }
  }
  def("abs", [t(["number"])], args => func_abs(args))
  def("avg", [t(["array-number"])], args => func_avg(args))
  def("ceil", [t(["number"])], args => func_ceil_floor(args, Double::ceil))
  def("contains", [t(["array", "string"]), any], func_contains)
  def("ends_with", [t(["string"]), t(["string"])], args => func_ends_with(args))
  def("floor", [t(["number"])], args => func_ceil_floor(args, Double::floor))
  def("join", [t(["string"]), t(["array-string"])], args => func_join(args))
  def("keys", [t(["object"])], args => func_keys(args))
  def("length", [t(["string", "array", "object"])], args => func_length(args))
  def("map", [t(["expref"]), t(["array"])], func_map)
  def("max", [t(["array-number", "array-string"])], args => func_min_max(
    args, ">",
  ))
  def("max_by", [t(["array"]), t(["expref"])], func_max_by)
  def("merge", [ArgSpec::new(["object"], variadic=true)], func_merge)
  def("min", [t(["array-number", "array-string"])], args => func_min_max(
    args, "<",
  ))
  def("min_by", [t(["array"]), t(["expref"])], func_min_by)
  def("not_null", [ArgSpec::new([], variadic=true)], func_not_null)
  def("reverse", [t(["array", "string"])], args => func_reverse(args))
  def("sort", [t(["array-string", "array-number"])], func_sort)
  def("sort_by", [t(["array"]), t(["expref"])], func_sort_by)
  def("starts_with", [t(["string"]), t(["string"])], args => func_starts_with(args))
  def("sum", [t(["array-number"])], args => func_sum(args))
  def("to_array", [any], func_to_array)
  def("to_number", [any], func_to_number)
  def("to_string", [any], args => func_to_string(args))
  def("type", [any], args => func_type(args))
  def("values", [t(["object"])], args => func_values(args))
  table
}
