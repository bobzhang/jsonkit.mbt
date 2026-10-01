# bobzhang/referencing

A faithful MoonBit port of [python-jsonschema/referencing](https://github.com/python-jsonschema/referencing):
cross-specification, implementation-agnostic JSON referencing — the engine
behind `$ref`, `$dynamicRef` and `$recursiveRef` resolution in
python-jsonschema.

Packages:

| package | upstream | contents |
| --- | --- | --- |
| `bobzhang/referencing` | `referencing`, `referencing.exceptions`, `referencing.retrieval` (and the definitions behind `referencing.jsonschema`) | `Specification`, `Resource`, `Registry`, `Resolver`, `Resolved`, `Retrieved`, `Anchor`, `ReferencingError`, `to_cached_resource` |
| `bobzhang/referencing/jsonschema` | `referencing.jsonschema` | `draft202012()` … `draft3()`, `specification_with`, `dynamic_anchor`, `lookup_recursive_ref`, `empty_registry`, the `$id`/anchor rules (re-exported from the root) |
| `bobzhang/referencing/urllib` | `urllib.parse` | `urljoin`, `urlsplit`, `urlparse`, `urlunsplit`, `urlunparse`, `urldefrag`, `unquote` — exact ports, tested against CPython |

## Registries and resolvers

Resources are `Json` documents paired with a `Specification`. Registries are
immutable (backed by persistent hash maps): every "modification" returns a new
registry, and subresources are discovered lazily ("crawled") on demand.

```mbt check
///|
test "resolve a reference" {
  let schema : Json = {
    "$id": "https://example.com/person",
    "$defs": { "name": { "$anchor": "name", "type": "string" } },
  }
  let resource = @referencing.draft202012().create_resource(schema)
  let registry = @referencing.Registry::new().with_resource(
    "https://example.com/person", resource,
  )
  let resolver = registry.resolver()
  // by URI + JSON pointer
  let resolved = resolver.lookup("https://example.com/person#/$defs/name")
  json_inspect(resolved.contents, content={
    "$anchor": "name",
    "type": "string",
  })
  // by plain-name anchor
  let by_anchor = resolver.lookup("https://example.com/person#name")
  assert_true(by_anchor.contents == resolved.contents)
  // `resolved.resolver` carries the new base URI (and dynamic scope) for
  // resolving references found *inside* the resolved contents
  inspect(resolved.resolver.base_uri(), content="https://example.com/person")
}
```

`Resource::from_contents` detects the specification from `$schema`; with a
`default_specification` it falls back to it instead of raising:

```mbt check
///|
test "detect specifications" {
  let resource = @referencing.Resource::from_contents({
    "$schema": "http://json-schema.org/draft-07/schema#",
  })
  inspect(resource.specification, content="<Specification name='draft-07'>")
  let fallback = @referencing.Resource::from_contents(
    { "type": "integer" },
    default_specification=@referencing.draft202012(),
  )
  inspect(fallback.specification, content="<Specification name='draft2020-12'>")
}
```

## Errors

All errors are constructors of the `ReferencingError` suberror, and their
`Show` output is exactly Python's `str(error)`. `Resolver::lookup` raises a
generic `Error` (custom callbacks may raise anything); use
`@referencing.is_unresolvable(error)` for Python's
`except referencing.exceptions.Unresolvable` (which also catches
`PointerToNowhere`, `NoSuchAnchor` and `InvalidAnchor`), and
`ReferencingError::from_error` to get at the details.

```mbt check
///|
test "unresolvable references" {
  let resolver = @referencing.Registry::new().resolver_with_root(
    @referencing.Resource::new_opaque({ "foo": {} }),
  )
  try resolver.lookup("#/foo/bar") catch {
    error => {
      assert_true(@referencing.is_unresolvable(error))
      inspect(error, content="'/foo/bar' does not exist within {'foo': {}}")
    }
  } noraise {
    _ => fail("expected an error")
  }
}
```

## Retrieval

A registry can be given a `retrieve` closure, called for unknown URIs;
`to_cached_resource` turns a "URI to serialized JSON" function into a
caching retriever:

```mbt check
///|
test "retrieval" {
  let retrieve = @referencing.to_cached_resource(uri => {
    guard uri == "urn:example:positive" else {
      raise @referencing.NoSuchResource(reference=uri)
    }
    "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"minimum\": 0}"
  })
  let resolver = @referencing.Registry::new(retrieve~).resolver()
  let resolved = resolver.lookup("urn:example:positive")
  json_inspect(resolved.contents, content={
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "minimum": 0,
  })
  // the registry inside the returned resolver now contains the resource
  assert_true(resolved.resolver.registry().contains("urn:example:positive"))
}
```

## Dynamic and recursive references

```mbt check
///|
test "dynamic scope" {
  let root = @referencing.draft202012().create_resource({
    "$id": "https://example.com/tree",
    "$dynamicAnchor": "node",
    "$defs": { "strict": { "$id": "strict", "$dynamicAnchor": "node" } },
  })
  let resolver = @referencing.Registry::new()
    .with_resource("https://example.com/tree", root)
    .resolver()
  let tree = resolver.lookup("https://example.com/tree")
  let strict = tree.resolver.lookup("strict")
  let scope = strict.resolver.dynamic_scope().map(pair => pair.0).to_array()
  assert_eq(scope, ["https://example.com/tree"])
  // `#node` is a dynamic anchor: the outermost one in the dynamic scope wins
  let node = strict.resolver.lookup("#node")
  assert_true(node.contents == root.contents)
}
```

`@referencing.lookup_recursive_ref(resolver)` implements draft 2019-09's
`$recursiveRef: "#"`.

## Differences from upstream

* **Errors.** Python's exception classes are constructors of one
  `ReferencingError` suberror (plus `UnknownDialect`, which upstream defines
  in `referencing.jsonschema`). The `ref` attribute is named `reference`
  (`ref` is a reserved word in MoonBit). `Unretrievable` carries the
  retriever's error as `cause` (Python's `__cause__`). Upstream's exception
  subclassing is replaced by `ReferencingError::is_unresolvable` /
  `is_unresolvable`. Where Python raises a builtin `ValueError`
  (malformed IPv6 URLs in `urlsplit`/`urljoin`, conflicting retrievers in
  `Registry::combine`), we raise `@urllib.ValueError`.
* **Naming.** `Specification.OPAQUE` is `opaque_specification` and
  `Resource.opaque` is `Resource::new_opaque` (`opaque` is reserved).
  `registry[uri]` is `Registry::at`; `resource @ registry` is
  `Registry::with_identified_resource(s)`; `Specification.detect` (class or
  instance method) is `Specification::detect(contents, default?)`.
  `DRAFT202012` etc. are functions (`draft202012()`, always returning the
  same object) because their callbacks refer back to `specification_with`,
  which MoonBit rejects as a cycle among top-level values.
* **Package layout.** The JSON Schema specifications are defined in the root
  package (`Specification::detect` needs them and packages cannot be
  mutually dependent) and re-exported by `bobzhang/referencing/jsonschema`.
* **Anchors.** The `referencing.typing.Anchor` protocol is a single `Anchor`
  struct with a `kind` tag (`"Anchor"`, `"DynamicAnchor"`, or custom via
  `Anchor::custom`) and an optional resolve closure; `DynamicAnchor(...)` is
  `dynamic_anchor(...)` and `isinstance(a, DynamicAnchor)` is
  `a.is_dynamic()`.
* **Ill-typed documents.** Where upstream would crash with a Python
  `TypeError`/`AttributeError`/`ValueError` on ill-typed JSON (e.g. a numeric
  `$id`, `properties` that is not an object, a non-integer array index in a
  JSON pointer, a pointer through a number), we ignore the keyword or raise
  `PointerToNowhere` respectively. A non-string `$schema` with a default
  specification falls back to the default. Python's `int()` accepts Unicode
  digits in array indices; we accept ASCII digits only.
* **Equality.** Callbacks (`Specification` fields, `retrieve`) compare by
  identity, as in Python; `Specification`s compare by identity or by name and
  identical callbacks.
* **Iteration order.** Sets of keywords are iterated in the order upstream
  lists them (Python's set order is unspecified); JSON objects in insertion
  order; registries in (unspecified) hash order.
* **`retrieval.to_cached_resource`** takes the retrieve function as its first
  argument (instead of being a decorator factory) and is specialized to
  `String` documents; caches are `unbounded_cache()` (default) or
  `lru_cache(maxsize=...)`. As with `functools.lru_cache`, errors are not
  cached.
* **`urllib`.** `urlsplit` skips Python's NFKC check of non-ASCII netlocs
  (`_checknetloc`). `py_repr` of floats in error messages approximates
  Python's `repr`.
* **Suite.** All 296 referencing-suite files pass, except the 12
  `rfc3986-normalization-*` files which upstream also marks as expected
  failures ("APIs need to change for proper URL support"); the generated
  tests assert that they still fail.
