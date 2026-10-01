///|
/// Schemes for which `urljoin` resolves relative references
/// (Python's `urllib.parse.uses_relative`).
pub let uses_relative : ReadOnlyArray[String] = [
  "", "ftp", "http", "gopher", "nntp", "imap", "wais", "file", "https", "shttp",
  "mms", "prospero", "rtsp", "rtsps", "rtspu", "sftp", "svn", "svn+ssh", "ws", "wss",
]

///|
/// Schemes which use a network location (Python's `urllib.parse.uses_netloc`).
pub let uses_netloc : ReadOnlyArray[String] = [
  "", "ftp", "http", "gopher", "nntp", "telnet", "imap", "wais", "file", "mms",
  "https", "shttp", "snews", "prospero", "rtsp", "rtsps", "rtspu", "rsync", "svn",
  "svn+ssh", "sftp", "nfs", "git", "git+ssh", "ws", "wss", "itms-services",
]

///|
/// Schemes which support `;params` (Python's `urllib.parse.uses_params`).
pub let uses_params : ReadOnlyArray[String] = [
  "", "ftp", "hdl", "prospero", "http", "imap", "https", "shttp", "rtsp", "rtsps",
  "rtspu", "sip", "sips", "mms", "sftp", "tel",
]

///|
fn in_list(list : ReadOnlyArray[String], s : String) -> Bool {
  list.contains(s)
}

///|
/// The result of `urlsplit`: `<scheme>://<netloc>/<path>?<query>#<fragment>`.
pub(all) struct SplitResult {
  scheme : String
  netloc : String
  path : String
  query : String
  fragment : String
} derive(Debug, Eq)

///|
/// The result of `urlparse`, which additionally splits `;params` off the path.
pub(all) struct ParseResult {
  scheme : String
  netloc : String
  path : String
  params : String
  query : String
  fragment : String
} derive(Debug, Eq)

///|
/// The result of `urldefrag`.
pub(all) struct DefragResult {
  url : String
  fragment : String
} derive(Debug, Eq)

///|
/// Reassemble the URL (Python's `SplitResult.geturl()`).
pub fn SplitResult::geturl(self : SplitResult) -> String {
  urlunsplit(self.scheme, self.netloc, self.path, self.query, self.fragment)
}

///|
/// Reassemble the URL (Python's `ParseResult.geturl()`).
pub fn ParseResult::geturl(self : ParseResult) -> String {
  urlunparse(
    self.scheme,
    self.netloc,
    self.path,
    self.params,
    self.query,
    self.fragment,
  )
}

///|
/// Reassemble the URL (Python's `DefragResult.geturl()`).
pub fn DefragResult::geturl(self : DefragResult) -> String {
  if self.fragment != "" {
    self.url + "#" + self.fragment
  } else {
    self.url
  }
}

///|
fn is_c0_control_or_space(c : UInt16) -> Bool {
  c <= 0x20
}

///|
fn lstrip_c0(s : String) -> String {
  let mut i = 0
  while i < s.length() && is_c0_control_or_space(s[i]) {
    i += 1
  }
  substr(s, i)
}

///|
fn strip_c0(s : String) -> String {
  let s = lstrip_c0(s)
  let mut j = s.length()
  while j > 0 && is_c0_control_or_space(s[j - 1]) {
    j -= 1
  }
  substr(s, 0, end=j)
}

///|
fn is_scheme_char(c : UInt16) -> Bool {
  is_ascii_alpha(c) || is_ascii_digit(c) || c == '+' || c == '-' || c == '.'
}

///|
fn split_netloc(url : String, start : Int) -> (String, String) {
  let mut delim = url.length()
  for i in start..<url.length() {
    let c = url[i]
    if c == '/' || c == '?' || c == '#' {
      delim = i
      break
    }
  }
  (substr(url, start, end=delim), substr(url, delim))
}

///|
/// Parse a URL into 5 components, exactly like Python's
/// `urllib.parse.urlsplit(url, scheme='', allow_fragments=True)`.
///
/// Raises `ValueError` for malformed bracketed (IPv6 / IPvFuture) hosts.
/// Note that `%` escapes are not expanded.
pub fn urlsplit(
  url : String,
  scheme? : String = "",
  allow_fragments? : Bool = true,
) -> SplitResult raise ValueError {
  let mut url = lstrip_c0(url)
  let mut scheme = strip_c0(scheme)
  for b in ["\t", "\r", "\n"] {
    url = url.replace_all(old=b, new="")
    scheme = scheme.replace_all(old=b, new="")
  }
  let mut netloc = ""
  let mut query = ""
  let mut fragment = ""
  if url.find(":") is Some(i) && i > 0 && is_ascii_alpha(url[0]) {
    let mut all_scheme_chars = true
    for j in 0..<i {
      if !is_scheme_char(url[j]) {
        all_scheme_chars = false
        break
      }
    }
    if all_scheme_chars {
      scheme = ascii_lower(substr(url, 0, end=i))
      url = substr(url, i + 1)
    }
  }
  if url.has_prefix("//") {
    let (n, rest) = split_netloc(url, 2)
    netloc = n
    url = rest
    let has_open = netloc.contains("[")
    let has_close = netloc.contains("]")
    if (has_open && !has_close) || (has_close && !has_open) {
      raise ValueError("Invalid IPv6 URL")
    }
    if has_open && has_close {
      check_bracketed_netloc(netloc)
    }
  }
  if allow_fragments && url.contains("#") {
    let (u, _, f) = partition(url, "#")
    url = u
    fragment = f
  }
  if url.contains("?") {
    let (u, _, q) = partition(url, "?")
    url = u
    query = q
  }
  { scheme, netloc, path: url, query, fragment }
}

///|
fn check_bracketed_netloc(netloc : String) -> Unit raise ValueError {
  let (_, _, hostname_and_port) = rpartition(netloc, "@")
  let (before_bracket, have_open_br, bracketed) = partition(
    hostname_and_port, "[",
  )
  let hostname = if have_open_br {
    if before_bracket != "" {
      raise ValueError("Invalid IPv6 URL")
    }
    let (hostname, _, port) = partition(bracketed, "]")
    if port != "" && !port.has_prefix(":") {
      raise ValueError("Invalid IPv6 URL")
    }
    hostname
  } else {
    let (hostname, _, _) = partition(hostname_and_port, ":")
    hostname
  }
  check_bracketed_host(hostname)
}

///|
fn check_bracketed_host(hostname : String) -> Unit raise ValueError {
  if hostname.has_prefix("v") {
    // \Av[a-fA-F0-9]+\..+\Z
    let mut i = 1
    while i < hostname.length() && is_ascii_hex(hostname[i]) {
      i += 1
    }
    let ok = i > 1 &&
      i < hostname.length() &&
      hostname[i] == '.' &&
      i + 1 < hostname.length()
    if !ok {
      raise ValueError("IPvFuture address is invalid")
    }
  } else if is_ipv4_address(hostname) {
    raise ValueError("An IPv4 address cannot be in brackets")
  } else if !is_ipv6_address(hostname) {
    raise ValueError(
      "\{py_str_repr(hostname)} does not appear to be an IPv4 or IPv6 address",
    )
  }
}

///|
fn split_params(url : String) -> (String, String) {
  let i = if url.contains("/") {
    let last_slash = url.rev_find("/").unwrap_or(0)
    match url.view(start_offset=last_slash).find(";") {
      Some(j) => last_slash + j
      None => return (url, "")
    }
  } else {
    url.find(";").unwrap_or(-1)
  }
  // Python: url[:i], url[i+1:] (i == -1 only when there is no ';' at all,
  // which callers rule out)
  (substr(url, 0, end=i), substr(url, i + 1))
}

///|
/// Parse a URL into 6 components, exactly like Python's
/// `urllib.parse.urlparse(url, scheme='', allow_fragments=True)`.
pub fn urlparse(
  url : String,
  scheme? : String = "",
  allow_fragments? : Bool = true,
) -> ParseResult raise ValueError {
  let split = urlsplit(url, scheme~, allow_fragments~)
  let (path, params) = if in_list(uses_params, split.scheme) &&
    split.path.contains(";") {
    split_params(split.path)
  } else {
    (split.path, "")
  }
  {
    scheme: split.scheme,
    netloc: split.netloc,
    path,
    params,
    query: split.query,
    fragment: split.fragment,
  }
}

///|
/// Combine URL components back into a URL string, exactly like Python's
/// `urllib.parse.urlunsplit`.
pub fn urlunsplit(
  scheme : String,
  netloc : String,
  path : String,
  query : String,
  fragment : String,
) -> String {
  let mut url = path
  if netloc != "" {
    if url != "" && !url.has_prefix("/") {
      url = "/" + url
    }
    url = "//" + netloc + url
  } else if url.has_prefix("//") {
    url = "//" + url
  } else if scheme != "" &&
    in_list(uses_netloc, scheme) &&
    (url == "" || url.has_prefix("/")) {
    url = "//" + url
  }
  if scheme != "" {
    url = scheme + ":" + url
  }
  if query != "" {
    url = url + "?" + query
  }
  if fragment != "" {
    url = url + "#" + fragment
  }
  url
}

///|
/// Combine URL components back into a URL string, exactly like Python's
/// `urllib.parse.urlunparse`.
pub fn urlunparse(
  scheme : String,
  netloc : String,
  path : String,
  params : String,
  query : String,
  fragment : String,
) -> String {
  let path = if params != "" { "\{path};\{params}" } else { path }
  urlunsplit(scheme, netloc, path, query, fragment)
}

///|
/// Remove any fragment from `url`, exactly like Python's
/// `urllib.parse.urldefrag`.
///
/// If the URL contains no `#`, it is returned unchanged with an empty fragment.
pub fn urldefrag(url : String) -> DefragResult raise ValueError {
  if url.contains("#") {
    let p = urlparse(url)
    {
      url: urlunparse(p.scheme, p.netloc, p.path, p.params, p.query, ""),
      fragment: p.fragment,
    }
  } else {
    { url, fragment: "" }
  }
}
