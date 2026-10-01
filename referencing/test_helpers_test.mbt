// Shared fixtures for the black-box tests (ported from upstream's
// referencing/tests/test_core.py).

///|
fn str_member(contents : Json, key : String) -> String? {
  match contents {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Upstream's `ID_AND_CHILDREN` test specification.
let id_and_children : @referencing.Specification = @referencing.Specification::new(
  name="id-and-children",
  id_of=contents => str_member(contents, "ID"),
  subresources_of=contents => {
    match contents {
      Object(obj) =>
        match obj.get("children") {
          Some(Array(children)) => children
          _ => []
        }
      _ => []
    }
  },
  anchors_in=(specification, contents) => {
    match contents {
      Object(obj) =>
        match obj.get("anchors") {
          Some(Object(anchors)) =>
            anchors
            .iter()
            .map(pair => {
              @referencing.Anchor::new(
                name=pair.0,
                resource=specification.create_resource(pair.1),
              )
            })
            .to_array()
          _ => []
        }
      _ => []
    }
  },
  maybe_in_subresource=(segments, resolver, subresource) => {
    let mut all_children = true
    for i, segment in segments {
      if i % 2 == 0 && !segment.is_key("children") {
        all_children = false
      }
    }
    if segments.length() % 2 == 0 && all_children {
      resolver.in_subresource(subresource)
    } else {
      resolver
    }
  },
)

///|
/// A retriever suitable for use in tests which expect it never to be used.
fn blow_up(_uri : String) -> @referencing.Resource raise {
  fail("This retrieve function expects to never be called!")
}

///|
fn opaque_resource(contents : Json) -> @referencing.Resource {
  @referencing.Resource::new_opaque(contents)
}
