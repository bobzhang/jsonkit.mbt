// A port of `jsonschema-specifications`: the JSON Schema meta-schemas and
// vocabularies, embedded in the package and parsed on first use.

///|
let parsed : Map[String, Json] = Map([])

///|
fn parse_source(source : (String, String, String)) -> Json {
  let (id, _, text) = source
  match parsed.get(id) {
    Some(j) => j
    None => {
      let j = @pycompat.loads(text) catch {
        e => abort("invalid embedded schema \{id}: \{e}")
      }
      parsed[id] = j
      j
    }
  }
}

///|
/// Every shipped schema as `(id, contents)`, where `id` is the schema's own
/// `$id` (or `id` for drafts 3 and 4), e.g.
/// `http://json-schema.org/draft-07/schema#` or
/// `https://json-schema.org/draft/2020-12/meta/core`.
pub fn schemas() -> Array[(String, Json)] {
  schema_sources.map(s => (s.0, parse_source(s)))
}

///|
/// The contents of the schema with the given URI (a trailing empty fragment
/// is ignored, as `referencing.Registry` does), if shipped.
pub fn contents(uri : String) -> Json? {
  let normalized = if uri.has_suffix("#") {
    uri.unsafe_substring(start=0, end=uri.length() - 1)
  } else {
    uri
  }
  for source in schema_sources {
    let id = source.0
    let id = if id.has_suffix("#") {
      id.unsafe_substring(start=0, end=id.length() - 1)
    } else {
      id
    }
    if id == normalized {
      return Some(parse_source(source))
    }
  }
  None
}
