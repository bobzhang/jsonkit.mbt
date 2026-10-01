///|
/// Whether a number's source spelling makes it a Python `float`.
fn repr_is_float(r : String) -> Bool {
  r.iter().any(c => c is ('.' | 'e' | 'E' | 'N' | 'I'))
}

///|
/// Python `isinstance(x, int) and not isinstance(x, bool)`.
///
/// A `Json::Number` is a Python `int` when it carries an integer spelling in
/// `repr~`, or when it has no spelling and is a finite whole number (numbers
/// built in MoonBit code via `Json::number(1.0)` count as ints; use
/// `Json::number(1.0, repr="1.0")` to build a Python float `1.0`).
pub fn is_int(j : Json) -> Bool {
  match j {
    Number(d, repr=None) => is_whole(d)
    Number(_, repr=Some(r)) => !repr_is_float(r)
    _ => false
  }
}

///|
/// Python `isinstance(x, float)`.
pub fn is_float(j : Json) -> Bool {
  j is Number(_) && !is_int(j)
}

///|
/// Python `isinstance(x, numbers.Number) and not isinstance(x, bool)`.
pub fn is_number(j : Json) -> Bool {
  j is Number(_)
}

///|
/// `float.is_integer()`.
pub fn is_whole(d : Double) -> Bool {
  !d.is_nan() && !d.is_inf() && d == d.floor()
}

///|
/// The exact value of a whole, finite double as a `BigInt`.
pub fn bigint_of_whole_double(d : Double) -> @bigint.BigInt {
  if d.abs() < 9.0e18 {
    return @bigint.BigInt::from_int64(d.to_int64())
  }
  let bits = d.reinterpret_as_uint64()
  let exp = ((bits >> 52) & 0x7FFUL).to_int() - 1075
  let mant = (bits & 0xFFFFFFFFFFFFFUL) | 0x10000000000000UL
  let m = @bigint.BigInt::from_uint64(mant)
  let v = if exp >= 0 { m.shl(exp) } else { m.shr(-exp) }
  if d < 0.0 {
    v.neg()
  } else {
    v
  }
}

///|
/// The exact value of a Python `int` JSON number. Only meaningful when
/// `is_int(j)`.
pub fn int_value(j : Json) -> @bigint.BigInt {
  match j {
    Number(_, repr=Some(r)) if !repr_is_float(r) =>
      @bigint.BigInt::from_string(normalize_int_token(r))
    Number(d, ..) => bigint_of_whole_double(d)
    _ => @bigint.BigInt::from_int(0)
  }
}

///|
/// The double value of a JSON number (`float(x)` for ints that fit).
pub fn number_value(j : Json) -> Double {
  match j {
    Number(d, ..) => d
    _ => @double.not_a_number
  }
}

///|
/// Compare a Python int with a finite or infinite float exactly; `None` when
/// unordered (NaN).
fn compare_int_float(n : @bigint.BigInt, f : Double) -> Int? {
  if f.is_nan() {
    None
  } else if f.is_pos_inf() {
    Some(-1)
  } else if f.is_neg_inf() {
    Some(1)
  } else {
    let fl = f.floor()
    let c = n.compare(bigint_of_whole_double(fl))
    if c <= 0 && f != fl {
      // n <= floor(f) < f
      Some(-1)
    } else {
      Some(c)
    }
  }
}

///|
/// Python numeric comparison of two JSON numbers (`int` and `float` are
/// compared exactly, like Python does). Returns `None` when the operands are
/// unordered (a NaN is involved) or not both numbers.
pub fn compare_numbers(a : Json, b : Json) -> Int? {
  guard a is Number(da, ..) && b is Number(db, ..) else { return None }
  match (is_int(a), is_int(b)) {
    (true, true) =>
      if da.abs() < 9.0e15 && db.abs() < 9.0e15 {
        Some(da.compare(db))
      } else {
        Some(int_value(a).compare(int_value(b)))
      }
    (true, false) => compare_int_float(int_value(a), db)
    (false, true) => compare_int_float(int_value(b), da).map(c => -c)
    (false, false) =>
      if da.is_nan() || db.is_nan() {
        None
      } else {
        Some(da.compare(db))
      }
  }
}

///|
/// Python `a == b` for two JSON numbers.
pub fn numbers_equal(a : Json, b : Json) -> Bool {
  compare_numbers(a, b) == Some(0)
}

///|
/// An exact rational `num / den` with `den > 0` (a power of two for floats).
priv struct Rational {
  num : @bigint.BigInt
  den : @bigint.BigInt
}

///|
fn rational_of(j : Json) -> Rational {
  let one = @bigint.BigInt::from_int(1)
  if is_int(j) {
    return { num: int_value(j), den: one, }
  }
  let d = number_value(j)
  // d is finite here
  let bits = d.reinterpret_as_uint64()
  let biased = ((bits >> 52) & 0x7FFUL).to_int()
  let frac = bits & 0xFFFFFFFFFFFFFUL
  let (mant, exp) = if biased == 0 {
    (frac, -1074)
  } else {
    (frac | 0x10000000000000UL, biased - 1075)
  }
  let m = @bigint.BigInt::from_uint64(mant)
  let m = if d < 0.0 { m.neg() } else { m }
  if exp >= 0 {
    { num: m.shl(exp), den: one, }
  } else {
    { num: m, den: one.shl(-exp), }
  }
}

///|
/// Port of the `multipleOf` keyword's arithmetic: returns whether
/// `instance` FAILS to be a multiple of `db` under Python semantics.
///
/// ```python
/// if isinstance(dB, float):
///     quotient = instance / dB
///     try:
///         failed = int(quotient) != quotient
///     except OverflowError:
///         failed = (Fraction(instance) / Fraction(dB)).denominator != 1
/// else:
///     failed = instance % dB
/// ```
pub fn multiple_of_failed(
  instance : Json,
  db : Json,
) -> Bool raise ArithmeticError {
  // float(x) of a Python int: OverflowError when it does not fit a double
  let to_float = (j : Json) => {
    let v = number_value(j)
    if is_int(j) && v.is_inf() {
      raise OverflowError("int too large to convert to float")
    }
    v
  }
  if is_float(db) {
    let dbv = number_value(db)
    let iv = to_float(instance)
    if dbv == 0.0 {
      raise ZeroDivisionError("float division by zero")
    }
    let quotient = iv / dbv
    if quotient.is_nan() {
      raise ValueError("cannot convert float NaN to integer")
    } else if quotient.is_inf() {
      // int(quotient) overflows: upstream falls back to exact fractions
      if iv.is_inf() {
        raise OverflowError("cannot convert Infinity to integer ratio")
      }
      let a = rational_of(instance)
      let b = rational_of(db)
      // (a.num / a.den) / (b.num / b.den) = a.num * b.den / (a.den * b.num)
      let n = a.num * b.den
      let d = a.den * b.num
      !n.mod(d).is_zero()
    } else {
      quotient.trunc() != quotient
    }
  } else if is_float(instance) {
    // float % int
    let dbv = to_float(db)
    if dbv == 0.0 {
      raise ZeroDivisionError("float modulo by zero")
    }
    let r = number_value(instance) % dbv
    r.is_nan() || r != 0.0
  } else {
    let a = int_value(instance)
    let b = int_value(db)
    if b.is_zero() {
      raise ZeroDivisionError("integer modulo by zero")
    }
    !a.mod(b).is_zero()
  }
}

///|
/// Python arithmetic errors raised by the numeric helpers.
pub suberror ArithmeticError {
  OverflowError(String)
  ValueError(String)
  ZeroDivisionError(String)
}

///|
pub impl Show for ArithmeticError with fn output(self, logger) {
  match self {
    OverflowError(m) => logger.write_string("OverflowError: \{m}")
    ValueError(m) => logger.write_string("ValueError: \{m}")
    ZeroDivisionError(m) => logger.write_string("ZeroDivisionError: \{m}")
  }
}
