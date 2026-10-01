///|
/// Join a base URL and a possibly relative URL to form an absolute
/// interpretation of the latter, exactly like Python's
/// `urllib.parse.urljoin(base, url, allow_fragments=True)`.
///
/// This mirrors Python's quirks: relative resolution only happens when the
/// scheme of `url` (defaulting to the base's) equals the base's scheme *and*
/// is listed in `uses_relative` (so e.g. `urn:` and `tag:` bases are never
/// joined against), the network location is only inherited for schemes in
/// `uses_netloc`, and excess `..` segments are dropped (RFC 3986).
///
/// ```mbt check
/// test {
///   inspect(
///     @urllib.urljoin("http://example.com/a/b", "../c"),
///     content="http://example.com/c",
///   )
///   inspect(@urllib.urljoin("urn:example:foo", "#bar"), content="#bar")
/// }
/// ```
pub fn urljoin(
  base : String,
  url : String,
  allow_fragments? : Bool = true,
) -> String raise ValueError {
  if base == "" {
    return url
  }
  if url == "" {
    return base
  }
  let b = urlparse(base, scheme="", allow_fragments~)
  let u = urlparse(url, scheme=b.scheme, allow_fragments~)
  let scheme = u.scheme
  let mut netloc = u.netloc
  let mut path = u.path
  let mut params = u.params
  let mut query = u.query
  let fragment = u.fragment
  if scheme != b.scheme || !in_list(uses_relative, scheme) {
    return url
  }
  if in_list(uses_netloc, scheme) {
    if netloc != "" {
      return urlunparse(scheme, netloc, path, params, query, fragment)
    }
    netloc = b.netloc
  }
  if path == "" && params == "" {
    path = b.path
    params = b.params
    if query == "" {
      query = b.query
    }
    return urlunparse(scheme, netloc, path, params, query, fragment)
  }
  let base_parts = split_all(b.path, "/")
  if base_parts[base_parts.length() - 1] != "" {
    // the last item is not a directory, so will not be taken into account
    // in resolving the relative path
    base_parts.pop() |> ignore
  }
  let segments = if path.has_prefix("/") {
    split_all(path, "/")
  } else {
    let all = base_parts
    all.append(split_all(path, "/"))
    // filter out elements that would cause redundant slashes on re-joining
    // the resolved_path
    if all.length() > 2 {
      let middle = all[1:all.length() - 1].iter().filter(s => s != "").to_array()
      [all[0], ..middle, all[all.length() - 1]]
    } else {
      all
    }
  }
  let resolved_path : Array[String] = []
  for seg in segments {
    if seg == ".." {
      resolved_path.pop() |> ignore
    } else if seg == "." {
      continue
    } else {
      resolved_path.push(seg)
    }
  }
  let last = segments[segments.length() - 1]
  if last == "." || last == ".." {
    // if the last segment was a relative dir, then we need to append the
    // trailing '/'
    resolved_path.push("")
  }
  let joined = resolved_path.join("/")
  path = if joined == "" { "/" } else { joined }
  urlunparse(scheme, netloc, path, params, query, fragment)
}
