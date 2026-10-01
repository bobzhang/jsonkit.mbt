///|
/// A caching strategy for retrieval functions (Python passes e.g.
/// `functools.lru_cache(maxsize=...)` as `cache`): it wraps a retrieve
/// function into a caching one.
pub type RetrieveCache = ((String) -> Resource raise) -> (String) -> Resource raise

///|
/// An unbounded cache (Python's `lru_cache(maxsize=None)`). Errors are not
/// cached.
pub fn unbounded_cache() -> RetrieveCache {
  retrieve => {
    let cache : Map[String, Resource] = Map([])
    uri => {
      match cache.get(uri) {
        Some(resource) => resource
        None => {
          let resource = retrieve(uri)
          cache[uri] = resource
          resource
        }
      }
    }
  }
}

///|
/// A least-recently-used cache holding at most `maxsize` resources (Python's
/// `functools.lru_cache(maxsize=maxsize)`). Errors are not cached.
pub fn lru_cache(maxsize~ : Int) -> RetrieveCache {
  retrieve => {
    // `Map` preserves insertion order: the first entry is the least recently
    // used one.
    let cache : Map[String, Resource] = Map([])
    uri => {
      match cache.get(uri) {
        Some(resource) => {
          cache.remove(uri)
          cache[uri] = resource
          resource
        }
        None => {
          let resource = retrieve(uri)
          cache[uri] = resource
          if cache.length() > maxsize {
            if cache.keys().head() is Some(oldest) {
              cache.remove(oldest)
            }
          }
          resource
        }
      }
    }
  }
}

///|
/// Create a retriever which caches its return values from a simpler function
/// returning serialized documents (Python's
/// `referencing.retrieval.to_cached_resource(cache, loads, from_contents)`
/// applied to `retrieve`).
///
/// * `loads` deserializes the document (default: `@json.parse`).
/// * `from_contents` creates the resource (default:
///   `Resource::from_contents` without a default specification).
/// * `cache` is the caching strategy (default: `unbounded_cache()`).
///
/// The result is suitable for `Registry::new(retrieve=...)`.
///
/// ```mbt check
/// test {
///   let calls = []
///   let retrieve = @referencing.to_cached_resource(uri => {
///     calls.push(uri)
///     "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"foo\": \"bar\"}"
///   })
///   let one = @referencing.Registry::new(retrieve~).get_or_retrieve(
///     "urn:example:foo",
///   )
///   let two = @referencing.Registry::new(retrieve~).get_or_retrieve(
///     "urn:example:foo",
///   )
///   inspect(
///     one.value.contents.stringify(),
///     content=(
///       #|{"$schema":"https://json-schema.org/draft/2020-12/schema","foo":"bar"}
///     ),
///   )
///   assert_true(physical_equal(one.value, two.value))
///   assert_eq(calls, ["urn:example:foo"])
/// }
/// ```
pub fn to_cached_resource(
  retrieve : (String) -> String raise,
  cache? : RetrieveCache = unbounded_cache(),
  loads? : (String) -> Json raise = s => @json.parse(s),
  from_contents? : (Json) -> Resource raise = contents => {
    Resource::from_contents(contents)
  },
) -> (String) -> Resource raise {
  cache(uri => from_contents(loads(retrieve(uri))))
}
