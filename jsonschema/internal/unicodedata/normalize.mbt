///|
const S_BASE = 0xAC00

///|
const L_BASE = 0x1100

///|
const V_BASE = 0x1161

///|
const T_BASE = 0x11A7

///|
const L_COUNT = 19

///|
const V_COUNT = 21

///|
const T_COUNT = 28

///|
const N_COUNT = 588 // V_COUNT * T_COUNT

///|
const S_COUNT = 11172 // L_COUNT * N_COUNT

///|
fn decomp_index(cp : Int) -> Int? {
  for lo = 0, hi = decomp_cps.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if decomp_cps[mid] < cp {
      continue mid + 1, hi
    } else if decomp_cps[mid] > cp {
      continue lo, mid
    } else {
      break Some(mid)
    }
  } nobreak {
    None
  }
}

///|
fn decompose_into(out : Array[Int], cp : Int) -> Unit {
  let s = cp - S_BASE
  if s >= 0 && s < S_COUNT {
    out.push(L_BASE + s / N_COUNT)
    out.push(V_BASE + s % N_COUNT / T_COUNT)
    let t = s % T_COUNT
    if t != 0 {
      out.push(T_BASE + t)
    }
    return
  }
  match decomp_index(cp) {
    Some(i) =>
      for j in decomp_offsets[i]..<decomp_offsets[i + 1] {
        decompose_into(out, decomp_data[j])
      }
    None => out.push(cp)
  }
}

///|
fn compose_pair(a : Int, b : Int) -> Int? {
  // Hangul LV / LVT
  let l = a - L_BASE
  if l >= 0 && l < L_COUNT {
    let v = b - V_BASE
    if v >= 0 && v < V_COUNT {
      return Some(S_BASE + (l * V_COUNT + v) * T_COUNT)
    }
  }
  let s = a - S_BASE
  if s >= 0 && s < S_COUNT && s % T_COUNT == 0 {
    let t = b - T_BASE
    if t > 0 && t < T_COUNT {
      return Some(a + t)
    }
  }
  let n = compose_triples.length() / 3
  for lo = 0, hi = n; lo < hi; {
    let mid = lo + (hi - lo) / 2
    let x = compose_triples[3 * mid]
    let y = compose_triples[3 * mid + 1]
    if x < a || (x == a && y < b) {
      continue mid + 1, hi
    } else if x == a && y == b {
      break Some(compose_triples[3 * mid + 2])
    } else {
      continue lo, mid
    }
  } nobreak {
    None
  }
}

///|
/// `unicodedata.normalize("NFC", ...)` over code points.
pub fn nfc(cps : ArrayView[Int]) -> Array[Int] {
  // canonical decomposition
  let d = []
  for cp in cps {
    decompose_into(d, cp)
  }
  // canonical ordering (stable insertion sort of non-starter runs)
  for i in 1..<d.length() {
    let cc = combining(d[i])
    if cc == 0 {
      continue
    }
    let mut j = i
    while j > 0 {
      let pc = combining(d[j - 1])
      if pc <= cc {
        break
      }
      let tmp = d[j - 1]
      d[j - 1] = d[j]
      d[j] = tmp
      j -= 1
    }
  }
  // canonical composition
  let out : Array[Int] = []
  let mut starter = -1
  let mut last_cc = -1
  for c in d {
    let cc = combining(c)
    if starter >= 0 && (last_cc == -1 || (last_cc != 0 && last_cc < cc)) {
      if compose_pair(out[starter], c) is Some(composite) {
        out[starter] = composite
        continue
      }
    }
    if cc == 0 {
      starter = out.length()
      last_cc = -1
    } else {
      last_cc = cc
    }
    out.push(c)
  }
  out
}
