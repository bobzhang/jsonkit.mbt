///|
/// Mirrors Python's builtin `ValueError`, as raised by `urllib.parse`
/// (e.g. `Invalid IPv6 URL`). It is also reused by the root
/// `bobzhang/referencing` package wherever upstream raises `ValueError`.
pub(all) suberror ValueError {
  ValueError(String)
} derive(Debug, Eq)

///|
/// `str()` of the error: the message itself.
pub impl Show for ValueError with fn output(self, logger) {
  match self {
    ValueError(msg) => logger.write_string(msg)
  }
}
