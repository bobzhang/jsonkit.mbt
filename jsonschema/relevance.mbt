///|
/// Keywords whose errors are considered weak matches by default.
pub let weak_matches : Array[String] = ["anyOf", "oneOf"]

///|
/// Keywords whose errors are considered strong matches by default.
pub let strong_matches : Array[String] = []

///|
/// The relevance of an error: upstream's tuple
/// `(-len(error.path), validator not in weak, validator in strong,
/// not error._matches_type())`, compared lexicographically (higher is more
/// relevant).
pub(all) struct Relevance {
  neg_path_length : Int
  not_weak : Bool
  strong : Bool
  not_matching_type : Bool
} derive(Eq, Compare, Debug)

///|
/// Create a key function that can be used to sort errors by relevance.
///
/// `weak` keywords are superseded by other same-level errors; `strong`
/// keywords take priority.
pub fn by_relevance(
  weak? : ArrayView[String] = weak_matches,
  strong? : ArrayView[String] = strong_matches,
) -> (ValidationError) -> Relevance {
  let weak = weak.to_owned()
  let strong = strong.to_owned()
  fn(error) {
    let keyword = error.keyword()
    let in_ = (set : Array[String]) => match keyword {
      Some(k) => set.contains(k)
      None => false
    }
    {
      neg_path_length: -error.path.length(),
      not_weak: !in_(weak),
      strong: in_(strong),
      not_matching_type: !error.matches_type(),
    }
  }
}

///|
/// A key function (e.g. to sort with) which sorts errors by relevance.
pub fn relevance(error : ValidationError) -> Relevance {
  by_relevance()(error)
}

///|
/// Find the most relevant error along with its key, computing each key once.
///
/// Equally relevant errors are settled by picking the one which appears
/// earlier in the instance.
fn most_relevant(
  errors : Iter[ValidationError],
  key : (ValidationError) -> Relevance,
) -> (Relevance, ValidationError)? {
  let mut best : (Relevance, ValidationError)? = None
  for error in errors {
    let error_key = key(error)
    match best {
      None => best = Some((error_key, error))
      Some((best_key, best_error)) =>
        if error_key > best_key ||
          (error_key == best_key && path_less(error.path, best_error.path)) {
          best = Some((error_key, error))
        }
    }
  }
  best
}

///|
/// Try to find an error that appears to be the best match among given
/// errors.
///
/// In general, errors that are higher up in the instance (i.e. for which
/// `path` is shorter) are considered better matches, since they indicate
/// "more" is wrong with the instance.
///
/// If the resulting match is either `oneOf` or `anyOf`, the *opposite*
/// assumption is made -- i.e. the deepest error is picked among the most
/// relevant errors in each separate subschema (preferring subschemas which
/// produced fewer errors when tied).
///
/// Returns `None` if there were no errors.
pub fn best_match(
  errors : Iter[ValidationError],
  key? : (ValidationError) -> Relevance = relevance,
) -> ValidationError? {
  guard most_relevant(errors, key) is Some((_, first)) else { return None }
  let mut best = first
  while best.context.length() > 0 {
    // Group the errors by the subschema which produced them.
    let groups : Array[(PathItem?, Array[ValidationError])] = []
    for error in best.context {
      let index = error.schema_path.get(0)
      match groups.search_by(g => g.0 == index) {
        Some(i) => groups[i].1.push(error)
        None => groups.push((index, [error]))
      }
    }
    // Rank each subschema by how deep its most relevant error is, and
    // amongst those equally deep, by how few errors it produced.
    let mut best_rank : (Relevance, Int)? = None
    let mut best_in_subschema : ValidationError? = None
    let mut tied = false
    for group in groups {
      let errors_in_subschema = group.1
      guard most_relevant(errors_in_subschema.iter(), key)
        is Some((error_key, error)) else {
        continue
      }
      let rank = (error_key, errors_in_subschema.length())
      match best_rank {
        None => {
          best_rank = Some(rank)
          best_in_subschema = Some(error)
          tied = false
        }
        Some(r) =>
          if rank < r {
            best_rank = Some(rank)
            best_in_subschema = Some(error)
            tied = false
          } else if rank == r {
            tied = true
          }
      }
    }
    // If multiple subschemas rank equally we can't tell which was intended.
    if tied {
      break
    }
    best = best_in_subschema.unwrap()
  }
  Some(best)
}

///|
/// Python's lexicographic comparison of two path deques.
fn path_less(a : Array[PathItem], b : Array[PathItem]) -> Bool {
  for i in 0..<@cmp.minimum(a.length(), b.length()) {
    let c = a[i].compare(b[i])
    if c != 0 {
      return c < 0
    }
  }
  a.length() < b.length()
}
