///|
/// A lazily produced sequence of validation errors: the counterpart of the
/// generators upstream's keyword functions and `iter_errors` return.
///
/// Nothing is computed until the sequence is consumed, and consumers that
/// stop early (`first`, `is_empty`, a `for`-style loop that breaks) stop the
/// validation work right there, exactly like advancing a Python generator
/// only as far as needed. Errors that are not validation errors (unknown
/// types, unresolvable references, ...) are raised while consuming.
///
/// Each consumption re-runs the computation.
pub struct Errors {
  priv run : ((ValidationError) -> Bool raise) -> Bool raise
}

///|
/// A sequence produced by `run`, which must pass each error to its
/// argument (a "yield" callback returning whether to go on), stopping and
/// returning `false` as soon as that returns `false`; `run` returns `true`
/// once it has produced all its errors.
pub fn Errors::new(
  run : ((ValidationError) -> Bool raise) -> Bool raise,
) -> Errors {
  { run, }
}

///|
/// No errors.
pub fn Errors::empty() -> Errors {
  { run: _ => true, }
}

///|
/// A single error.
pub fn Errors::single(error : ValidationError) -> Errors {
  { run: yield_ => yield_(error), }
}

///|
/// Feed the errors to `yield_`, stopping early when it returns `false`.
/// Returns whether all errors were consumed.
pub fn Errors::run(
  self : Errors,
  yield_ : (ValidationError) -> Bool raise,
) -> Bool raise {
  (self.run)(yield_)
}

///|
/// Call `f` on each error.
pub fn Errors::each(
  self : Errors,
  f : (ValidationError) -> Unit raise,
) -> Unit raise {
  ignore(
    (self.run)(e => {
      f(e)
      true
    }),
  )
}

///|
/// The first error, if any (Python's `next(errors, None)`); stops the
/// computation right after it.
pub fn Errors::first(self : Errors) -> ValidationError? raise {
  let mut found = None
  ignore(
    (self.run)(e => {
      found = Some(e)
      false
    }),
  )
  found
}

///|
/// Whether there are no errors (stops at the first one).
pub fn Errors::is_empty(self : Errors) -> Bool raise {
  self.first() is None
}

///|
/// All the errors (Python's `list(errors)`).
pub fn Errors::to_array(self : Errors) -> Array[ValidationError] raise {
  let out = []
  self.each(e => out.push(e))
  out
}

///|
/// Transform each error as it passes through.
pub fn Errors::map(
  self : Errors,
  f : (ValidationError) -> ValidationError raise,
) -> Errors {
  { run: yield_ => (self.run)(e => yield_(f(e))), }
}
