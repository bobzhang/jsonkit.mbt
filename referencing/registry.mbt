///|
/// A value retrieved from a `Registry`, along with the registry which
/// ultimately contained it (which may have been crawled or have had a
/// resource retrieved into it).
pub(all) struct Retrieved[T] {
  value : T
  registry : Registry
}

///|
/// A registry of `Resource`s, each identified by their canonical URIs.
///
/// Registries store a collection of in-memory resources, and optionally
/// enable additional resources which may be stored elsewhere (e.g. in a
/// database, a separate set of files, over the network, etc.).
///
/// They also lazily walk their known resources, looking for subresources
/// within them. In other words, subresources contained within any added
/// resources will be retrievable via their own IDs (though this discovery of
/// subresources will be delayed until necessary).
///
/// Registries are immutable (backed by persistent hash maps, so copies are
/// cheap), and their methods return new instances of the registry with the
/// additional resources added to them.
///
/// The `retrieve` closure can be used to configure retrieval of resources
/// dynamically, either over the network, from a database, or the like. It is
/// called if any URI not present in the registry is accessed. It must either
/// return a `Resource` or else raise `NoSuchResource` indicating that the
/// resource does not exist even according to the retrieval logic; any other
/// error is wrapped in `Unretrievable`.
pub struct Registry {
  priv resources : @hashmap.HashMap[String, Resource]
  priv anchors : @hashmap.HashMap[(String, String), Anchor]
  priv uncrawled : @hashset.HashSet[String]
  priv retrieve : ((String) -> Resource raise)?
}

///|
/// Create a registry (Python's `Registry(resources, anchors=..., retrieve=...)`).
///
/// Note that, exactly as upstream, `resources` passed here are considered
/// already crawled (they are not walked for subresources); use
/// `Registry::with_resources` to add resources which should be crawled.
/// Without `retrieve`, unknown URIs raise `NoSuchResource`.
pub fn Registry::new(
  resources? : ArrayView[(String, Resource)] = [],
  anchors? : ArrayView[((String, String), Anchor)] = [],
  retrieve? : (String) -> Resource raise,
) -> Registry {
  {
    resources: @hashmap.HashMap(resources),
    anchors: @hashmap.HashMap(anchors),
    uncrawled: @hashset.HashSet::new(),
    retrieve,
  }
}

///|
/// Return the (already crawled) `Resource` identified by the given URI
/// (Python's `registry[uri]`). Trailing `#`s are ignored.
///
/// Raises `NoSuchResource` if it is not present.
pub fn Registry::at(
  self : Registry,
  uri : String,
) -> Resource raise ReferencingError {
  match self.resources.get(rstrip_hash(uri)) {
    Some(resource) => resource
    None => raise NoSuchResource(reference=uri)
  }
}

///|
/// Return the (already crawled) `Resource` identified by the given URI, if any
/// (Python's `registry.get(uri)`).
pub fn Registry::get(self : Registry, uri : String) -> Resource? {
  self.resources.get(rstrip_hash(uri))
}

///|
/// Whether a (crawled) resource is identified by the given URI
/// (Python's `uri in registry`).
pub fn Registry::contains(self : Registry, uri : String) -> Bool {
  self.resources.contains(rstrip_hash(uri))
}

///|
/// Iterate over all crawled URIs in the registry (in unspecified order).
pub fn Registry::iter(self : Registry) -> Iter[String] {
  self.resources.keys()
}

///|
/// Iterate over all crawled `(uri, resource)` pairs (Python's `.items()`).
pub fn Registry::iter2(self : Registry) -> Iter2[String, Resource] {
  self.resources.iter2()
}

///|
/// All crawled URIs in the registry.
pub fn Registry::keys(self : Registry) -> Iter[String] {
  self.resources.keys()
}

///|
/// Count the total number of fully crawled resources in this registry.
pub fn Registry::length(self : Registry) -> Int {
  self.resources.length()
}

///|
/// Whether the registry has no resources (Python's `not registry`).
pub fn Registry::is_empty(self : Registry) -> Bool {
  self.resources.length() == 0
}

///|
/// The number of added resources not yet crawled.
pub fn Registry::uncrawled_count(self : Registry) -> Int {
  self.uncrawled.length()
}

///|
/// Create a new registry with resources added using their internal IDs
/// (Python's `[resources...] @ registry`).
///
/// Raises `NoInternalID` if any resource has no internal ID (e.g. the `$id`
/// keyword in modern JSON Schema versions).
pub fn Registry::with_identified_resources(
  self : Registry,
  new : ArrayView[Resource],
) -> Registry raise ReferencingError {
  let mut resources = self.resources
  let mut uncrawled = self.uncrawled
  for resource in new {
    guard resource.id() is Some(id) else { raise NoInternalID(resource~) }
    uncrawled = uncrawled.add(id)
    resources = resources.add(id, resource)
  }
  { ..self, resources, uncrawled, }
}

///|
/// Create a new registry with the resource added using its internal ID
/// (Python's `resource @ registry`).
pub fn Registry::with_identified_resource(
  self : Registry,
  resource : Resource,
) -> Registry raise ReferencingError {
  self.with_identified_resources([resource])
}

///|
/// Get a resource from the registry, crawling or retrieving if necessary.
///
/// May involve crawling to find the given URI if it is not already known, so
/// the returned object contains both the resource as well as the registry
/// which ultimately contained it (including any newly retrieved resource).
pub fn Registry::get_or_retrieve(
  self : Registry,
  uri : String,
) -> Retrieved[Resource] raise {
  if self.resources.get(uri) is Some(resource) {
    return { registry: self, value: resource, }
  }
  let registry = self.crawl()
  if registry.resources.get(uri) is Some(resource) {
    return { registry, value: resource, }
  }
  guard registry.retrieve is Some(retrieve) else {
    raise NoSuchResource(reference=uri)
  }
  let resource = retrieve(uri) catch {
    CannotDetermineSpecification(..) as error => raise error
    NoSuchResource(..) as error => raise error
    error => raise Unretrievable(reference=uri, cause=Some(error))
  }
  { registry: registry.with_resource(uri, resource), value: resource, }
}

///|
/// Return a registry with the resource identified by a given URI removed.
///
/// Raises `NoSuchResource` if it is not present.
pub fn Registry::remove(
  self : Registry,
  uri : String,
) -> Registry raise ReferencingError {
  if !self.resources.contains(uri) {
    raise NoSuchResource(reference=uri)
  }
  {
    ..self,
    resources: self.resources.remove(uri),
    uncrawled: self.uncrawled.remove(uri),
    anchors: self.anchors.filter((k, _) => k.0 != uri),
  }
}

///|
/// Retrieve a given anchor from a resource which must already be crawled.
///
/// Raises `NoSuchResource` if the resource is unknown, `InvalidAnchor` if the
/// name contains a `/` (and so could never be a plain-name anchor), and
/// `NoSuchAnchor` otherwise if the anchor is missing.
pub fn Registry::anchor(
  self : Registry,
  uri : String,
  name : String,
) -> Retrieved[Anchor] raise {
  if self.anchors.get((uri, name)) is Some(value) {
    return { value, registry: self, }
  }
  let registry = self.crawl()
  if registry.anchors.get((uri, name)) is Some(value) {
    return { value, registry, }
  }
  let resource = self.at(uri)
  if resource.id() is Some(canonical_uri) &&
    registry.anchors.get((canonical_uri, name)) is Some(value) {
    return { value, registry, }
  }
  if name.contains("/") {
    raise InvalidAnchor(reference=uri, resource~, anchor=name)
  }
  raise NoSuchAnchor(reference=uri, resource~, anchor=name)
}

///|
/// Retrieve the (already crawled) contents identified by the given URI.
pub fn Registry::contents(
  self : Registry,
  uri : String,
) -> Json raise ReferencingError {
  self.at(uri).contents
}

///|
/// Crawl all added resources, discovering subresources (and anchors).
///
/// Raises only if joining an identifier onto its base URI fails
/// (`@urllib.ValueError`, e.g. for malformed IPv6 hosts).
pub fn Registry::crawl(self : Registry) -> Registry raise @urllib.ValueError {
  let mut resources = self.resources
  let mut anchors = self.anchors
  let uncrawled : Array[(String, Resource)] = self.uncrawled
    .iter()
    .map(uri => (uri, resources.at(uri)))
    .to_array()
  while uncrawled.pop() is Some((uri, resource)) {
    let uri = match resource.id() {
      Some(id) => {
        let uri = @urllib.urljoin(uri, id)
        resources = resources.add(uri, resource)
        uri
      }
      None => uri
    }
    for each in resource.anchors() {
      anchors = anchors.add((uri, each.name), each)
    }
    for each in resource.subresources() {
      uncrawled.push((uri, each))
    }
  }
  { ..self, resources, anchors, uncrawled: @hashset.HashSet::new(), }
}

///|
/// Add the given `Resource` to the registry, without crawling it.
///
/// Trailing `#`s are stripped from the URI (empty fragment URIs are
/// equivalent to URIs without the fragment).
pub fn Registry::with_resource(
  self : Registry,
  uri : String,
  resource : Resource,
) -> Registry {
  self.with_resources([(uri, resource)])
}

///|
/// Add the given `Resource`s to the registry, without crawling them.
pub fn Registry::with_resources(
  self : Registry,
  pairs : ArrayView[(String, Resource)],
) -> Registry {
  let mut resources = self.resources
  let mut uncrawled = self.uncrawled
  for pair in pairs {
    let uri = rstrip_hash(pair.0)
    uncrawled = uncrawled.add(uri)
    resources = resources.add(uri, pair.1)
  }
  { ..self, resources, uncrawled, }
}

///|
/// Add the given contents to the registry, autodetecting when necessary
/// (see `Resource::from_contents`).
pub fn Registry::with_contents(
  self : Registry,
  pairs : ArrayView[(String, Json)],
  default_specification? : Specification,
) -> Registry raise ReferencingError {
  let resources = []
  for pair in pairs {
    resources.push(
      (pair.0, Resource::from_contents(pair.1, default_specification?)),
    )
  }
  self.with_resources(resources)
}

///|
/// Combine together one or more other registries, producing a unified one.
///
/// Later registries' resources take precedence. Raises `ValueError` if two
/// registries have conflicting (non-default) retrieval functions; retrieval
/// functions are compared by identity.
pub fn Registry::combine(
  self : Registry,
  registries : ArrayView[Registry],
) -> Registry raise @urllib.ValueError {
  if registries.length() == 1 && physical_equal(registries[0], self) {
    return self
  }
  let mut resources = self.resources
  let mut anchors = self.anchors
  let mut uncrawled = self.uncrawled
  let mut retrieve = self.retrieve
  for registry in registries {
    resources = registry.resources.fold(init=resources, (acc, k, v) => {
      acc.add(k, v)
    })
    anchors = registry.anchors.fold(init=anchors, (acc, k, v) => acc.add(k, v))
    uncrawled = registry.uncrawled
      .iter()
      .fold(init=uncrawled, (acc, k) => acc.add(k))
    if registry.retrieve is Some(theirs) {
      if retrieve is Some(ours) && !physical_equal(theirs, ours) {
        raise @urllib.ValueError(
          "Cannot combine registries with conflicting retrieval functions.",
        )
      }
      retrieve = Some(theirs)
    }
  }
  { resources, anchors, uncrawled, retrieve, }
}

///|
/// Return a `Resolver` which resolves references against this registry.
pub fn Registry::resolver(self : Registry, base_uri? : String = "") -> Resolver {
  Resolver::new(base_uri~, registry=self)
}

///|
/// Return a `Resolver` with a specific root resource, which is added to the
/// registry under its ID (or the empty URI if it has none).
pub fn Registry::resolver_with_root(
  self : Registry,
  resource : Resource,
) -> Resolver {
  let uri = resource.id().unwrap_or("")
  Resolver::new(base_uri=uri, registry=self.with_resource(uri, resource))
}

///|
/// Registries are equal when they have equal resources, anchors and uncrawled
/// URIs, and the same retrieval function (compared by identity).
pub impl Eq for Registry with fn equal(self, other) {
  self.resources == other.resources &&
  self.anchors == other.anchors &&
  self.uncrawled == other.uncrawled &&
  (match (self.retrieve, other.retrieve) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  })
}

///|
/// `<Registry (2 resources, 1 uncrawled)>`, as Python's `repr`.
pub impl Show for Registry with fn output(self, logger) {
  let size = self.length()
  let pluralized = if size == 1 { "resource" } else { "resources" }
  let summary = if !self.uncrawled.is_empty() {
    let uncrawled = self.uncrawled.length()
    if uncrawled == size {
      "uncrawled \{pluralized}"
    } else {
      "\{pluralized}, \{uncrawled} uncrawled"
    }
  } else {
    pluralized
  }
  logger.write_string("<Registry (\{size} \{summary})>")
}
