// A port of CPython 3.13's `list.sort()` (Objects/listobject.c): timsort
// with powersort run merging, the 3.13 `count_run` (which also reverses
// "descending" runs containing equal elements), binary insertion sort and
// galloping merges.  Only `<` is used, exactly as in CPython, so the result
// is identical even when the comparison is not a total order (e.g. NaN).

///|
let min_gallop : Int = 7

///|
priv struct SortRun {
  base : Int
  mut len : Int
  mut power : Int
}

///|
priv struct MergeState {
  keys : Array[Json]
  values : Array[Json]
  mut min_gallop : Int
  pending : Array[SortRun]
  listlen : Int
}

///|
fn sort_lt(a : Json, b : Json) -> Bool raise JMESPathError {
  py_order("<", a, b)
}

///|
fn MergeState::reverse(self : MergeState, lo : Int, n : Int) -> Unit {
  let mut i = lo
  let mut j = lo + n - 1
  while i < j {
    let k = self.keys[i]
    self.keys[i] = self.keys[j]
    self.keys[j] = k
    let v = self.values[i]
    self.values[i] = self.values[j]
    self.values[j] = v
    i += 1
    j -= 1
  }
}

///|
/// Length of the run starting at `lo` (made ascending in place).
fn MergeState::count_run(
  self : MergeState,
  lo : Int,
  nremaining : Int,
) -> Int raise JMESPathError {
  let a = self.keys
  let next_smaller = (n : Int) => sort_lt(a[lo + n], a[lo + n - 1])
  let next_larger = (n : Int) => sort_lt(a[lo + n - 1], a[lo + n])
  // Try an ascending run first.
  let mut n = 1
  while n < nremaining {
    if next_smaller(n) {
      break
    }
    n += 1
  }
  if n == nremaining {
    return n
  }
  // a[n] is strictly less.
  if n > 1 {
    if sort_lt(a[lo], a[lo + n - 1]) {
      return n
    }
    // a[0] == a[n-1]: all equal so far; view it as a descending run.
    self.reverse(lo, n)
  }
  n += 1
  // Descending run.
  let mut neq = 0
  let reverse_last_neq = (n : Int, neq : Int) => {
    if neq > 0 {
      let neq = neq + 1
      self.reverse(lo + n - neq, neq)
    }
  }
  while n < nremaining {
    if next_smaller(n) {
      reverse_last_neq(n, neq)
      neq = 0
    } else if next_larger(n) {
      break
    } else {
      neq += 1
    }
    n += 1
  }
  reverse_last_neq(n, neq)
  self.reverse(lo, n)
  // It may be extended by a naturally increasing suffix.
  while n < nremaining {
    if next_smaller(n) {
      break
    }
    n += 1
  }
  n
}

///|
/// Binary insertion sort of `[lo, lo + n)`, where `[lo, lo + ok)` is sorted.
fn MergeState::binarysort(
  self : MergeState,
  lo : Int,
  n : Int,
  ok : Int,
) -> Unit raise JMESPathError {
  let a = self.keys
  let v = self.values
  let mut ok = if ok == 0 { 1 } else { ok }
  while ok < n {
    let mut l = 0
    let mut r = ok
    let pivot = a[lo + ok]
    let pivot_value = v[lo + ok]
    while l < r {
      let m = (l + r) >> 1
      if sort_lt(pivot, a[lo + m]) {
        r = m
      } else {
        l = m + 1
      }
    }
    let mut m = ok
    while m > l {
      a[lo + m] = a[lo + m - 1]
      v[lo + m] = v[lo + m - 1]
      m -= 1
    }
    a[lo + l] = pivot
    v[lo + l] = pivot_value
    ok += 1
  }
}

///|
/// Locate the proper position of `key` in the sorted `a[base:base+n]`:
/// the leftmost position where it could be inserted.
fn gallop_left(
  key : Json,
  a : Array[Json],
  base : Int,
  n : Int,
  hint : Int,
) -> Int raise JMESPathError {
  let mut lastofs = 0
  let mut ofs = 1
  if sort_lt(a[base + hint], key) {
    // a[hint] < key: gallop right.
    let maxofs = n - hint
    while ofs < maxofs {
      if sort_lt(a[base + hint + ofs], key) {
        lastofs = ofs
        ofs = (ofs << 1) + 1
      } else {
        break
      }
    }
    if ofs > maxofs {
      ofs = maxofs
    }
    lastofs += hint
    ofs += hint
  } else {
    // key <= a[hint]: gallop left.
    let maxofs = hint + 1
    while ofs < maxofs {
      if sort_lt(a[base + hint - ofs], key) {
        break
      }
      lastofs = ofs
      ofs = (ofs << 1) + 1
    }
    if ofs > maxofs {
      ofs = maxofs
    }
    let k = lastofs
    lastofs = hint - ofs
    ofs = hint - k
  }
  lastofs += 1
  while lastofs < ofs {
    let m = lastofs + ((ofs - lastofs) >> 1)
    if sort_lt(a[base + m], key) {
      lastofs = m + 1
    } else {
      ofs = m
    }
  }
  ofs
}

///|
/// Like `gallop_left`, but the rightmost position.
fn gallop_right(
  key : Json,
  a : Array[Json],
  base : Int,
  n : Int,
  hint : Int,
) -> Int raise JMESPathError {
  let mut lastofs = 0
  let mut ofs = 1
  if sort_lt(key, a[base + hint]) {
    // key < a[hint]: gallop left.
    let maxofs = hint + 1
    while ofs < maxofs {
      if sort_lt(key, a[base + hint - ofs]) {
        lastofs = ofs
        ofs = (ofs << 1) + 1
      } else {
        break
      }
    }
    if ofs > maxofs {
      ofs = maxofs
    }
    let k = lastofs
    lastofs = hint - ofs
    ofs = hint - k
  } else {
    // a[hint] <= key: gallop right.
    let maxofs = n - hint
    while ofs < maxofs {
      if sort_lt(key, a[base + hint + ofs]) {
        break
      }
      lastofs = ofs
      ofs = (ofs << 1) + 1
    }
    if ofs > maxofs {
      ofs = maxofs
    }
    lastofs += hint
    ofs += hint
  }
  lastofs += 1
  while lastofs < ofs {
    let m = lastofs + ((ofs - lastofs) >> 1)
    if sort_lt(key, a[base + m]) {
      ofs = m
    } else {
      lastofs = m + 1
    }
  }
  ofs
}

///|
/// Merge the adjacent runs `[pa, pa + na)` and `[pb, pb + nb)` in place,
/// with `na <= nb` (`merge_lo`).
fn MergeState::merge_lo(
  self : MergeState,
  pa : Int,
  na : Int,
  pb : Int,
  nb : Int,
) -> Unit raise JMESPathError {
  let keys = self.keys
  let values = self.values
  let tmp_keys = keys[pa:pa + na].to_owned()
  let tmp_values = values[pa:pa + na].to_owned()
  let mut dest = pa
  let mut pa = 0 // index into tmp
  let mut pb = pb
  let mut na = na
  let mut nb = nb
  let copy_b = () => {
    keys[dest] = keys[pb]
    values[dest] = values[pb]
    dest += 1
    pb += 1
  }
  let copy_a = () => {
    keys[dest] = tmp_keys[pa]
    values[dest] = tmp_values[pa]
    dest += 1
    pa += 1
  }
  // Returns true when the merge ended with a single A element left (CopyB).
  let body = () => {
    copy_b()
    nb -= 1
    if nb == 0 {
      return false
    }
    if na == 1 {
      return true
    }
    let mut min_gallop = self.min_gallop
    while true {
      let mut acount = 0
      let mut bcount = 0
      while true {
        if sort_lt(keys[pb], tmp_keys[pa]) {
          copy_b()
          bcount += 1
          acount = 0
          nb -= 1
          if nb == 0 {
            return false
          }
          if bcount >= min_gallop {
            break
          }
        } else {
          copy_a()
          acount += 1
          bcount = 0
          na -= 1
          if na == 1 {
            return true
          }
          if acount >= min_gallop {
            break
          }
        }
      }
      min_gallop += 1
      while true {
        if min_gallop > 1 {
          min_gallop -= 1
        }
        self.min_gallop = min_gallop
        let k = gallop_right(keys[pb], tmp_keys, pa, na, 0)
        acount = k
        if k > 0 {
          for _ in 0..<k {
            copy_a()
          }
          na -= k
          if na == 1 {
            return true
          }
          if na == 0 {
            return false
          }
        }
        copy_b()
        nb -= 1
        if nb == 0 {
          return false
        }
        let k = gallop_left(tmp_keys[pa], keys, pb, nb, 0)
        bcount = k
        if k > 0 {
          for _ in 0..<k {
            copy_b()
          }
          nb -= k
          if nb == 0 {
            return false
          }
        }
        copy_a()
        na -= 1
        if na == 1 {
          return true
        }
        if !(acount >= min_gallop_default() || bcount >= min_gallop_default()) {
          break
        }
      }
      min_gallop += 1
      self.min_gallop = min_gallop
    }
    false
  }
  let copy_b_tail = body()
  if copy_b_tail {
    // CopyB: the last element of A belongs at the end of the merge.
    for _ in 0..<nb {
      copy_b()
    }
    copy_a()
  } else {
    for _ in 0..<na {
      copy_a()
    }
  }
}

///|
fn min_gallop_default() -> Int {
  min_gallop
}

///|
/// Merge the adjacent runs `[pa, pa + na)` and `[pb, pb + nb)` in place,
/// with `na > nb` (`merge_hi`), working from the right.
fn MergeState::merge_hi(
  self : MergeState,
  pa : Int,
  na : Int,
  pb : Int,
  nb : Int,
) -> Unit raise JMESPathError {
  let keys = self.keys
  let values = self.values
  let tmp_keys = keys[pb:pb + nb].to_owned()
  let tmp_values = values[pb:pb + nb].to_owned()
  let basea = pa
  let mut dest = pb + nb - 1
  let mut pa = pa + na - 1 // index into keys
  let mut pb = nb - 1 // index into tmp
  let mut na = na
  let mut nb = nb
  let copy_a = () => {
    keys[dest] = keys[pa]
    values[dest] = values[pa]
    dest -= 1
    pa -= 1
  }
  let copy_b = () => {
    keys[dest] = tmp_keys[pb]
    values[dest] = tmp_values[pb]
    dest -= 1
    pb -= 1
  }
  // Returns true when the merge ended with a single B element left (CopyA).
  let body = () => {
    copy_a()
    na -= 1
    if na == 0 {
      return false
    }
    if nb == 1 {
      return true
    }
    let mut min_gallop = self.min_gallop
    while true {
      let mut acount = 0
      let mut bcount = 0
      while true {
        if sort_lt(tmp_keys[pb], keys[pa]) {
          copy_a()
          acount += 1
          bcount = 0
          na -= 1
          if na == 0 {
            return false
          }
          if acount >= min_gallop {
            break
          }
        } else {
          copy_b()
          bcount += 1
          acount = 0
          nb -= 1
          if nb == 1 {
            return true
          }
          if bcount >= min_gallop {
            break
          }
        }
      }
      min_gallop += 1
      while true {
        if min_gallop > 1 {
          min_gallop -= 1
        }
        self.min_gallop = min_gallop
        let k = na - gallop_right(tmp_keys[pb], keys, basea, na, na - 1)
        acount = k
        if k > 0 {
          for _ in 0..<k {
            copy_a()
          }
          na -= k
          if na == 0 {
            return false
          }
        }
        copy_b()
        nb -= 1
        if nb == 1 {
          return true
        }
        let k = nb - gallop_left(keys[pa], tmp_keys, 0, nb, nb - 1)
        bcount = k
        if k > 0 {
          for _ in 0..<k {
            copy_b()
          }
          nb -= k
          if nb == 1 {
            return true
          }
          if nb == 0 {
            return false
          }
        }
        copy_a()
        na -= 1
        if na == 0 {
          return false
        }
        if !(acount >= min_gallop_default() || bcount >= min_gallop_default()) {
          break
        }
      }
      min_gallop += 1
      self.min_gallop = min_gallop
    }
    false
  }
  let copy_a_tail = body()
  if copy_a_tail {
    // CopyA: the first element of B belongs at the front of the merge.
    for _ in 0..<na {
      copy_a()
    }
    copy_b()
  } else {
    for _ in 0..<nb {
      copy_b()
    }
  }
}

///|
/// Merge the two runs at stack indices `i` and `i + 1` (`merge_at`).
fn MergeState::merge_at(self : MergeState, i : Int) -> Unit raise JMESPathError {
  let p = self.pending
  let mut pa = p[i].base
  let mut na = p[i].len
  let pb = p[i + 1].base
  let mut nb = p[i + 1].len
  p[i].len = na + nb
  if i == p.length() - 3 {
    p[i + 1] = p[i + 2]
  }
  p.pop() |> ignore
  // Where does b start in a?  Elements in a before that are in place.
  let k = gallop_right(self.keys[pb], self.keys, pa, na, 0)
  pa += k
  na -= k
  if na == 0 {
    return
  }
  // Where does a end in b?  Elements in b after that are in place.
  nb = gallop_left(self.keys[pa + na - 1], self.keys, pb, nb, nb - 1)
  if nb <= 0 {
    return
  }
  if na <= nb {
    self.merge_lo(pa, na, pb, nb)
  } else {
    self.merge_hi(pa, na, pb, nb)
  }
}

///|
/// Powersort's "power" of the boundary between two adjacent runs.
fn powerloop(s1 : Int, n1 : Int, n2 : Int, n : Int) -> Int {
  let mut result = 0
  let mut a = 2L * s1.to_int64() + n1.to_int64()
  let mut b = a + n1.to_int64() + n2.to_int64()
  let n = n.to_int64()
  while true {
    result += 1
    if a >= n {
      a -= n
      b -= n
    } else if b >= n {
      break
    }
    a = a << 1
    b = b << 1
  }
  result
}

///|
fn MergeState::found_new_run(
  self : MergeState,
  n2 : Int,
) -> Unit raise JMESPathError {
  let p = self.pending
  if p.length() > 0 {
    let s1 = p[p.length() - 1].base
    let n1 = p[p.length() - 1].len
    let power = powerloop(s1, n1, n2, self.listlen)
    while p.length() > 1 && p[p.length() - 2].power > power {
      self.merge_at(p.length() - 2)
    }
    p[p.length() - 1].power = power
  }
}

///|
fn MergeState::merge_force_collapse(
  self : MergeState,
) -> Unit raise JMESPathError {
  let p = self.pending
  while p.length() > 1 {
    let mut n = p.length() - 2
    if n > 0 && p[n - 1].len < p[n + 1].len {
      n -= 1
    }
    self.merge_at(n)
  }
}

///|
fn merge_compute_minrun(n : Int) -> Int {
  let mut n = n
  let mut r = 0
  while n >= 64 {
    r = r | (n & 1)
    n = n >> 1
  }
  n + r
}

///|
/// Sorts `keys` in place with CPython's algorithm, applying the same
/// permutation to `values`.
fn py_list_sort(
  keys : Array[Json],
  values : Array[Json],
) -> Unit raise JMESPathError {
  let n = keys.length()
  if n < 2 {
    return
  }
  let ms : MergeState = { keys, values, min_gallop, pending: [], listlen: n, }
  let minrun = merge_compute_minrun(n)
  let mut lo = 0
  let mut nremaining = n
  while nremaining > 0 {
    let mut run = ms.count_run(lo, nremaining)
    if run < minrun {
      let force = if nremaining <= minrun { nremaining } else { minrun }
      ms.binarysort(lo, force, run)
      run = force
    }
    ms.found_new_run(run)
    ms.pending.push({ base: lo, len: run, power: 0, })
    lo += run
    nremaining -= run
  }
  ms.merge_force_collapse()
}
