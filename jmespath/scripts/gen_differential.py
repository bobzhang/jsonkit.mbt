#!/usr/bin/env python3
"""Generate differential tests against the upstream Python implementation.

Each case is an (expression, given-JSON-text) pair.  The case is evaluated
with upstream jmespath.py (upstream/jmespath.py must be importable) and the
outcome is recorded exactly:

  ok:<json.dumps(result, separators=(',', ':'))>     (ensure_ascii=True)
  err:<exception class name>:<str(exception)>

The generated jmespath/differential_test.mbt checks that the MoonBit port
produces byte-identical outcomes (number spelling, error messages, ...).

Usage:  python3 jmespath/scripts/gen_differential.py
"""
import json
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
ROOT = os.path.dirname(PKG)
sys.path.insert(0, os.path.join(ROOT, "upstream", "jmespath.py"))

import jmespath  # noqa: E402

def _random_sort_cases():
    """Sorting inputs that exercise CPython's timsort, including NaN
    (no total order), duplicates of equal int/float values (stability is
    visible through the 1 vs 1.0 spelling) and long runs (galloping)."""
    rng = random.Random(20261001)
    cases = []
    atoms = ["0", "1", "2", "1.0", "2.0", "0.5", "NaN", "3", "-1"]
    for size in [3, 5, 8, 16, 33, 64, 65, 100, 130, 200, 257, 400]:
        for _ in range(3):
            kind = rng.choice(["random", "runs", "nan_heavy"])
            items = []
            if kind == "runs":
                while len(items) < size:
                    run = sorted(rng.randint(0, 50) for _ in range(rng.randint(1, 40)))
                    if rng.random() < 0.5:
                        run.reverse()
                    items += [str(x) if rng.random() < 0.7 else "%d.0" % x
                              for x in run]
                    if rng.random() < 0.3:
                        items.append("NaN")
                items = items[:size]
            elif kind == "nan_heavy":
                items = [rng.choice(["NaN", "NaN", "1", "2", "1.0"])
                         for _ in range(size)]
            else:
                items = [rng.choice(atoms) for _ in range(size)]
            data = "[" + ", ".join(items) + "]"
            cases.append(("sort(@)", data))
            objs = "[" + ", ".join('{"k": %s, "i": %d}' % (x, i)
                                     for i, x in enumerate(items)) + "]"
            cases.append(("sort_by(@, &k)[*].i", objs))
    for size in [10, 70, 300]:
        words = [rng.choice(["a", "b", "ab", "\\u00e9", "\\ud83d\\ude00",
                             "\\uffff", ""]) for _ in range(size)]
        cases.append(("sort(@)", "[" + ", ".join('"%s"' % w for w in words) + "]"))
    return cases


RANDOM_SORT_CASES = _random_sort_cases()

PEOPLE = '''[{"name": "a", "age": 30}, {"name": "b", "age": 20},
             {"name": "c", "age": 30}, {"name": "d", "age": 10}]'''

CASES = [
    # --- to_string / json.dumps number and string spelling
    ("to_string(@)", "1"),
    ("to_string(@)", "1.0"),
    ("to_string(@)", "1.5"),
    ("to_string(@)", "-0.0"),
    ("to_string(@)", "1e21"),
    ("to_string(@)", "1E+2"),
    ("to_string(@)", "1e-7"),
    ("to_string(@)", "0.0001"),
    ("to_string(@)", "1e16"),
    ("to_string(@)", "1e15"),
    ("to_string(@)", "0.1"),
    ("to_string(@)", "123456789012345678901234567890"),
    ("to_string(@)", "1e400"),
    ("to_string(@)", "-1e400"),
    ("to_string(@)", "NaN"),
    ("to_string(@)", '[1, 2.0, "\\u00e9", "\\ud83d\\ude00", "\\u007f", "\\u0000\\n\\t\\"\\\\/"]'),
    ("to_string(@)", '{"a": null, "b": [true, false], "\\u00e9": {}}'),
    ("to_string(`1.0`)", "{}"),
    ("to_string('\u00e9')", "{}"),
    ("@", "[1.0, 2.50, 3e0, -0, 1E400, NaN, -Infinity]"),
    ("`[1.0, 1e3, NaN, -Infinity]`", "{}"),
    # --- arithmetic functions keep Python int/float kinds
    ("sum(@)", "[1, 2, 3]"),
    ("sum(@)", "[1, 2.5, 3]"),
    ("sum(@)", "[0.1, 0.2, 0.3]"),
    ("sum(@)", "[1e100, 1.0, -1e100]"),
    ("sum(@)", "[]"),
    ("sum(@)", "[1.0]"),
    ("avg(@)", "[1, 2, 3]"),
    ("avg(@)", "[0.1, 0.2, 0.3]"),
    ("avg(@)", "[]"),
    ("abs(@)", "-3"),
    ("abs(@)", "-1.5"),
    ("abs(@)", "-1.0"),
    ("ceil(@)", "1.5"),
    ("ceil(@)", "-0.5"),
    ("ceil(@)", "2"),
    ("floor(@)", "-1.5"),
    ("floor(@)", "1.0"),
    ("ceil(@)", "1e400"),
    ("floor(@)", "NaN"),
    ("max(@)", "[1, 3.5, 2]"),
    ("min(@)", "[1.0, 1]"),
    ("max(@)", "[]"),
    ("sort(@)", "[3, 1.5, 2, 1]"),
    # --- to_number
    ("to_number(@)", '"1"'),
    ("to_number(@)", '" 42 "'),
    ("to_number(@)", '"1_000"'),
    ("to_number(@)", '"1__0"'),
    ("to_number(@)", '"_1"'),
    ("to_number(@)", '"+5"'),
    ("to_number(@)", '"-0"'),
    ("to_number(@)", '"007"'),
    ("to_number(@)", '"1.5"'),
    ("to_number(@)", '"1."'),
    ("to_number(@)", '".5"'),
    ("to_number(@)", '"1e3"'),
    ("to_number(@)", '"1E-3"'),
    ("to_number(@)", '"1e400"'),
    ("to_number(@)", '"inf"'),
    ("to_number(@)", '"-Infinity"'),
    ("to_number(@)", '"nan"'),
    ("to_number(@)", '"abc"'),
    ("to_number(@)", '""'),
    ("to_number(@)", '"0x10"'),
    ("to_number(@)", '"1 2"'),
    ("to_number(@)", '"12345678901234567890123"'),
    ("to_number(@)", "1.5"),
    ("to_number(@)", "true"),
    # --- code points vs UTF-16
    ("length(@)", '"\\ud83d\\ude00a"'),
    ("reverse(@)", '"a\\ud83d\\ude00b"'),
    ("sort(@)", '["b", "a", "\\ud83d\\ude00", "\\uffff", "aa", ""]'),
    ("max(@)", '["\\uffff", "\\ud83d\\ude00"]'),
    ("min(@)", '["\\uffff", "\\ud83d\\ude00"]'),
    ("[?@ < '\\uffff']", '["\\ud83d\\ude00", "\\ufffe"]'),
    ("a < b", '{"a": "\\uffff", "b": "\\ud83d\\ude00"}'),
    ("a < b", '{"a": "b", "b": "aa"}'),
    ("sort_by(@, &@)", '["\\ud83d\\ude00", "\\uffff", "a"]'),
    ("contains(@, '\\ud83d\\ude00')", '"x\\ud83d\\ude00y"'),
    ("starts_with(@, '\u00e9')", '"\u00e9t\u00e9"'),
    ("ends_with(@, 't\u00e9')", '"\u00e9t\u00e9"'),
    ("join('\u2713', @)", '["a", "\\ud83d\\ude00"]'),
    ('"\u2713"', '{"\u2713": 1}'),
    ("'\U0001F600'", "{}"),
    # --- equality and truthiness
    ("[`1`] == [`true`]", "{}"),
    ("`[1]` == `[true]`", "{}"),
    ("`1` == `true`", "{}"),
    ("`0` == `false`", "{}"),
    ("`2` == `true`", "{}"),
    ("`1.0` == `1`", "{}"),
    ("`{\"a\": 1}` == `{\"a\": true}`", "{}"),
    ("`{\"a\": 1, \"b\": 2}` == `{\"b\": 2, \"a\": 1}`", "{}"),
    ("contains(`[0]`, `false`)", "{}"),
    ("contains(`[1, 2]`, `true`)", "{}"),
    ("contains(`[[1]]`, `[true]`)", "{}"),
    ("!@", "0"),
    ("!@", "0.0"),
    ("!@", "1"),
    ("!@", '""'),
    ("!@", "[]"),
    ("!@", "{}"),
    ("!@", "null"),
    ("!@", '"x"'),
    ("@ || 'default'", "0"),
    ("@ && 'yes'", "[]"),
    ("[?@]", '[0, false, null, "", [], {}, "a", [0], {"a": null}, 0.0]'),
    # --- ordering comparisons
    ("`1` < `2`", "{}"),
    ("`1` < 'a'", "{}"),
    ("`1.5` >= 'a'", "{}"),
    ("'a' > `1`", "{}"),
    ("`true` < `false`", "{}"),
    ("`null` < `1`", "{}"),
    ("`[1]` < `[2]`", "{}"),
    ("a <= b", '{"a": NaN, "b": 1}'),
    # --- sort_by / min_by / max_by
    ("sort_by(@, &age)[*].name", PEOPLE),
    ("sort_by(@, &name)[*].name", PEOPLE),
    ("max_by(@, &age).name", PEOPLE),
    ("min_by(@, &age).name", PEOPLE),
    ("sort_by(@, &a)", '[{"a": true}]'),
    ("sort_by(@, &a)", '[{"a": 1}, {"a": "x"}]'),
    ("sort_by(@, &a)", '[{"a": 1}, {"b": 2}]'),
    ("min_by(@, &a)", '[{"a": 1}, {"a": "x"}]'),
    ("max_by(@, &a)", '[{"a": "x"}, {"a": 1}]'),
    ("max_by(@, &a)", '[{"a": 1}, {"a": null}]'),
    ("min_by(@, &a)", '[{"a": [1]}]'),
    ("sort_by(`[]`, &a)", "{}"),
    ("min_by(`[]`, &a)", "{}"),
    # --- function type errors (messages use Python reprs and type names)
    ("length(@)", "2"),
    ("length(@)", "1.5"),
    ("length(@)", "1e400"),
    ("length(@)", "true"),
    ("length(@)", "null"),
    ("abs(@)", '"x"'),
    ("abs(@)", '{"a\'b": [1, "x\\"y", null, true, 2.5]}'),
    ("abs(@)", '"it\'s"'),
    ("abs(@)", '["it\'s", "say \\"hi\\"", "both \' and \\"", "tab\\t", "\\u00e9", "\\u0001", "\\\\"]'),
    ("avg(@)", '["a"]'),
    ("avg(@)", "[1, true]"),
    ("sum(@)", "[null]"),
    ("max(@)", "[1, \"a\"]"),
    ("max(@)", "[\"a\", 1]"),
    ("max(@)", "[true]"),
    ("max(@)", "[[1]]"),
    ("sort(@)", "[{}, 1]"),
    ("join(', ', @)", "[1]"),
    ("join(`1`, @)", '["a"]'),
    ("map(&a, @)", '{"a": 1}'),
    ("map(@, @)", "[1]"),
    ("sort_by(@, @)", "[1]"),
    ("length(&a)", "{}"),
    ("keys(@)", "[]"),
    ("not_null()", "{}"),
    ("merge()", "{}"),
    ("type(&a)", "{}"),
    ("contains('abc', `1`)", "{}"),
    ("contains('abc', `null`)", "{}"),
    ("contains(`[\"a\"]`, &a)", "{}"),
    ("unknown(@)", "{}"),
    ("unknown(@, 'x')", "{}"),
    ("length()", "{}"),
    ("length(@, @)", "{}"),
    ("sort_by(@)", "{}"),
    # --- merge mirrors dict.update for unchecked arguments
    ("merge(@, `{\"b\": 2}`, `{\"a\": 3}`)", '{"a": 1, "c": 0}'),
    ("merge(@, `1`)", "{}"),
    ("merge(@, `null`)", "{}"),
    ("merge(@, `true`)", "{}"),
    ("merge(@, 'ab')", "{}"),
    ("merge(@, '')", "{}"),
    ("merge(@, `[]`)", "{}"),
    ("merge(@, `[[\"k\", 1], \"xy\"]`)", "{}"),
    ("merge(@, `[[1, 2, 3]]`)", "{}"),
    ("merge(@, `[1]`)", "{}"),
    ("merge(@, `[[[1], 2]]`)", "{}"),
    ("merge(@, `[[{}, 2]]`)", "{}"),
    ("merge(@, `[{\"a\": 1, \"b\": 2}]`)", "{}"),
    # --- slices and indices
    ("[::-1]", "[0, 1, 2, 3, 4]"),
    ("[10:-20:-1]", "[0, 1, 2, 3, 4]"),
    ("[-100:100]", "[0, 1, 2, 3, 4]"),
    ("[-2:]", "[0, 1, 2, 3, 4]"),
    ("[:-2:2]", "[0, 1, 2, 3, 4]"),
    ("[1:3:0]", "[0, 1, 2, 3, 4]"),
    ("[1:3:0]", "{}"),
    ("[-1]", "[0, 1, 2]"),
    ("[-4]", "[0, 1, 2]"),
    ("[3]", "[0, 1, 2]"),
    ("[0]", '"abc"'),
    ("[0:1]", '"abc"'),
    ("[99999999999]", "[1]"),
    ("[-99999999999]", "[1]"),
    ("[0][1:][0]", "[[1, 2, 3]]"),
    ("[*][0]", "[[1, 2], [3, 4]]"),
    # --- projections / multiselect / flatten
    ("*", '{"a": 1, "b": null, "c": 2}'),
    ("[*]", '[1, null, 2]'),
    ("[]", '[1, [2, [3]], null]'),
    ("{a: a, b: b}", "null"),
    ("[a, b]", "null"),
    ("{a: a, b: b}", "1"),
    ("a.{x: @}", '{"a": 0}'),
    ("foo[?bar > `1`].baz", '{"foo": [{"bar": 1, "baz": "x"}, {"bar": 2, "baz": "y"}, {"bar": "3", "baz": "z"}]}'),
    ("{a: b c: d}", '{"b": 1, "d": 2}'),
    ("f(a b)", "{}"),
    ("not_null(a b, c)", '{"b": 1, "c": 2}'),
    # --- literals and quoted identifiers
    ("`NaN`", "{}"),
    ("`-Infinity`", "{}"),
    ("`1e400`", "{}"),
    ("`  foo`", "{}"),
    ("`[1,]`", "{}"),
    ("`{\"a\": 1, \"a\": 2}`", "{}"),
    ("`\"\\u00e9\"`", "{}"),
    ("`\"\\ud83d\\ude00\"`", "{}"),
    ("`01`", "{}"),
    ("`foo\"bar`", "{}"),
    ("`\ufefffoo`", "{}"),
    ("'a\\'b'", "{}"),
    ("'a\\\\b'", "{}"),
    ('"\\u00e9"', '{"\u00e9": 1}'),
    ('"\\x"', "{}"),
    ('"a\tb"', "{}"),
    ('"\\uZZZZ"', "{}"),
    ('"\\u12"', "{}"),
    ('"abc', "{}"),
    ("'abc", "{}"),
    ("`abc", "{}"),
    # --- parse errors
    ("", "{}"),
    ("foo]baz", "{}"),
    ("foo.", "{}"),
    ("foo.1", "{}"),
    ("foo.`1`", "{}"),
    ("foo.{1: a}", "{}"),
    ("foo.[1", "{}"),
    ("foo[1", "{}"),
    ("foo[a", "{}"),
    ("foo[:::]", "{}"),
    ("foo[1:a]", "{}"),
    ("foo[*", "{}"),
    ("foo[*]]", "{}"),
    ("foo{", "{}"),
    ("*a", "{}"),
    ("!", "{}"),
    ("a !b", "{}"),
    ("@(a)", "{}"),
    ("\"f\"(a)", "{}"),
    ("(a", "{}"),
    ("a || ", "{}"),
    ("a = b", "{}"),
    ("a ^ b", "{}"),
    ("-", "{}"),
    ("--1", "{}"),
    ("a `{\"a\": [1, 2.5]}`", "{}"),
    ("[1] [2]", "{}"),
    ("\u00e9", "{}"),
    ("'\U0001F600' ]", "{}"),
    ("'\U0001F600' |", "{}"),
    ("a[?b", "{}"),
    ("&", "{}"),
    ("a.&b", "{}"),
    # --- loads (Python json.loads) error messages
    ("@", ""),
    ("@", "   "),
    ("@", "[1,]"),
    ("@", '{"a": 1,}'),
    ("@", '{"a" 1}'),
    ("@", "{a: 1}"),
    ("@", "[1 2]"),
    ("@", "[1] x"),
    ("@", '"abc'),
    ("@", '"a\\x"'),
    ("@", '"\\u12"'),
    ("@", '"\\uZZZZ"'),
    ("@", '"a\tb"'),
    ("@", "\n\n  [1,\n  ]"),
    ("@", "\ufeff[]"),
    ("@", "-"),
    ("@", "01"),
    ("@", "1."),
    ("@", ".5"),
    ("@", "tru"),
    ("@", '"éé" x'),
    # --- review fixes: slices with steps near the Int limits
    ("[1::2147483647]", "[0, 1, 2]"),
    ("[0::2147483647]", "[0, 1, 2]"),
    ("[::-2147483647]", "[0, 1, 2]"),
    ("[::-2147483648]", "[0, 1, 2]"),
    ("[1::-2147483648]", "[0, 1, 2]"),
    ("[-2147483648:2147483647]", "[0, 1, 2]"),
    ("[2147483647:-2147483648:-1]", "[0, 1, 2]"),
    ("[::99999999999]", "[0, 1, 2]"),
    ("[::-99999999999]", "[0, 1, 2]"),
    # --- review fixes: CPython sum() int -> float transition
    ("sum(@)", "[1, 1e16, -1e16]"),
    ("sum(@)", "[1e16, 1, -1e16]"),
    ("sum(@)", "[0.5, 1e16, 1, 1, -1e16]"),
    ("sum(@)", "[3, 0.1, 1e16, -1e16, 0.2]"),
    ("avg(@)", "[1, 1e16, -1e16]"),
    # --- review fixes: identity shortcut in container ==, `in`
    ("@ == @", "[NaN]"),
    ("@[0] == @[0]", "[NaN]"),
    ("@ == `[NaN]`", "[NaN]"),
    ("`[NaN]` == `[NaN]`", "{}"),
    ("{a: @[0]} == {a: @[0]}", "[NaN]"),
    ("[@[0]] == [@[1]]", "[NaN, NaN]"),
    ("contains(@, `NaN`)", "[NaN]"),
    ("contains(@, @[1])", "[1, NaN]"),
    ("contains(@, to_number('nan'))", "[NaN]"),
    ("[to_number('nan')] == [to_number('nan')]", "{}"),
    ("@ == @", "[1e400]"),
    # --- review fixes: string searches by code point
    ('contains(@, `"\\ud83d"`)', '"\\ud83d\\ude00"'),
    ('contains(@, `"\\ude00"`)', '"\\ud83d\\ude00"'),
    ('starts_with(@, `"\\ud83d"`)', '"\\ud83d\\ude00"'),
    ('ends_with(@, `"\\ude00"`)', '"\\ud83d\\ude00"'),
    ('contains(@, `"\\ud83d"`)', '"a\\ud83db"'),
    ("starts_with(@, '')", '""'),
    ("contains(@, '')", '""'),
    ("contains(@, 'ab')", '"a"'),
    # --- review fixes: int()/float() whitespace
    ("to_number(@)", '"\\u001c1"'),
    ("to_number(@)", '"1\\u001f"'),
    ("to_number(@)", '"\\u00a01\\u2000"'),
    ("to_number(@)", '"\\u000b1.5\\u000c"'),
    ("to_number(@)", '"\\u00851e2\\u3000"'),
    ("to_number(@)", '"\\u001d2.5"'),
] + RANDOM_SORT_CASES


def outcome(expression, given_text):
    try:
        given = json.loads(given_text)
        result = jmespath.search(expression, given)
        return "ok:" + json.dumps(result, separators=(",", ":"))
    except Exception as e:  # noqa: BLE001
        # Object addresses are not reproducible: "<... object at 0x...>".
        message = re.sub(r" at 0x[0-9a-f]+>", ">", str(e))
        return "err:%s:%s" % (type(e).__name__, message)


def mbt_string(s):
    out = ['"']
    for ch in s:
        code = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 0x20 or code == 0x7F:
            out.append("\\u{%x}" % code)
        elif 0xD800 <= code <= 0xDFFF:
            raise ValueError("lone surrogate in %r" % s)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


HELPERS = '''
///|
fn differential_error_class(e : @jmespath.JMESPathError) -> String {
  match e {
    ParseError(..) => "ParseError"
    IncompleteExpressionError(..) => "IncompleteExpressionError"
    LexerError(..) => "LexerError"
    ArityError(..) => "ArityError"
    VariadictArityError(..) => "VariadictArityError"
    JMESPathTypeError(..) => "JMESPathTypeError"
    EmptyExpressionError => "EmptyExpressionError"
    UnknownFunctionError(_) => "UnknownFunctionError"
    ValueError(_) => "ValueError"
    TypeError(_) => "TypeError"
    OverflowError(_) => "OverflowError"
  }
}

///|
fn differential_outcome(expression : String, given : String) -> String {
  try {
    let data = @jmespath.loads(given) catch {
      e => return "err:JSONDecodeError:\\{e}"
    }
    "ok:" + @jmespath.dumps(@jmespath.search(expression, data))
  } catch {
    e => "err:\\{differential_error_class(e)}:\\{e}"
  }
}
'''


def main():
    lines = [
        "// Code generated by scripts/gen_differential.py. DO NOT EDIT.",
        "// Expected outcomes were produced by upstream jmespath.py.",
        HELPERS,
    ]
    for i, (expression, given) in enumerate(CASES):
        expected = outcome(expression, given)
        lines += [
            "///|",
            "test %s {" % mbt_string("differential/%d: %s" % (i, expression)),
            "  assert_eq(",
            "    differential_outcome(",
            "      %s," % mbt_string(expression),
            "      %s," % mbt_string(given),
            "    ),",
            "    %s," % mbt_string(expected),
            "  )",
            "}",
            "",
        ]
    out = os.path.join(PKG, "differential_test.mbt")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("%s: %d cases" % (os.path.relpath(out, ROOT), len(CASES)))


if __name__ == "__main__":
    sys.exit(main())
