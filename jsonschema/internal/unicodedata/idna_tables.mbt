///|
/// `intranges_contain(cp, idnadata.codepoint_classes["PVALID"])`.
pub fn idna_is_pvalid(cp : Int) -> Bool {
  in_ranges(idna_pvalid_ranges, cp)
}

///|
/// `intranges_contain(cp, idnadata.codepoint_classes["CONTEXTJ"])`.
pub fn idna_is_contextj(cp : Int) -> Bool {
  in_ranges(idna_contextj_ranges, cp)
}

///|
/// `intranges_contain(cp, idnadata.codepoint_classes["CONTEXTO"])`.
pub fn idna_is_contexto(cp : Int) -> Bool {
  in_ranges(idna_contexto_ranges, cp)
}

///|
/// `intranges_contain(cp, idnadata.scripts[script])` for the scripts used by
/// the CONTEXTO rules.
pub fn idna_is_script(cp : Int, script : String) -> Bool {
  match script {
    "Greek" => in_ranges(idna_script_greek_ranges, cp)
    "Han" => in_ranges(idna_script_han_ranges, cp)
    "Hebrew" => in_ranges(idna_script_hebrew_ranges, cp)
    "Hiragana" => in_ranges(idna_script_hiragana_ranges, cp)
    "Katakana" => in_ranges(idna_script_katakana_ranges, cp)
    _ => false
  }
}

///|
/// `idna.core._joining_type(cp)`: one of `"C"`, `"D"`, `"L"`, `"R"`, `"T"`.
pub fn idna_joining_type(cp : Int) -> String? {
  if in_ranges(idna_joining_c_ranges, cp) {
    Some("C")
  } else if in_ranges(idna_joining_d_ranges, cp) {
    Some("D")
  } else if in_ranges(idna_joining_l_ranges, cp) {
    Some("L")
  } else if in_ranges(idna_joining_r_ranges, cp) {
    Some("R")
  } else if in_ranges(idna_joining_t_ranges, cp) {
    Some("T")
  } else {
    None
  }
}
