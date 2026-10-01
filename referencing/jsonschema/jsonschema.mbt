// Referencing implementations for JSON Schema specs (historic & current):
// the counterpart of Python's `referencing.jsonschema` module.
//
// Everything here is defined in the root `bobzhang/referencing` package (the
// specifications are needed by `Specification::detect`, and MoonBit packages
// cannot depend on each other cyclically) and re-exported under the upstream
// module layout.

///|
pub using @referencing {
  draft202012,
  draft201909,
  draft7,
  draft6,
  draft4,
  draft3,
  specification_with,
  dynamic_anchor,
  lookup_recursive_ref,
  empty_registry,
  dollar_id,
  legacy_dollar_id,
  legacy_id,
  anchors_2020,
  anchors_2019,
  legacy_anchor_in_dollar_id,
  legacy_anchor_in_id,
}
