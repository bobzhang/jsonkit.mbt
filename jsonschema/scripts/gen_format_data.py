#!/usr/bin/env python3
"""
Generate internal/formats/data.mbt: data taken from the (permissively
licensed) libraries python-jsonschema uses for format checking in its
``format-nongpl`` configuration:

* the RFC 3986 regular expressions of ``rfc3986-validator`` (MIT), used for
  ``uri`` / ``uri-reference``, as Python regex source (interpreted by the
  port of ``re`` in internal/regex),
* the RFC 3987 ABNF grammar of ``rfc3987-syntax`` (MIT), used for ``iri`` /
  ``iri-reference``. The grammar is not recursive, so its language is
  regular: each start rule is inlined into an equivalent Python regex
  (matched in full), checked here against the library itself,
* the CSS3 color names of ``webcolors`` (BSD-3-Clause).

Usage (needs ``rfc3986-validator``, ``rfc3987-syntax`` and ``webcolors``):

    python3 jsonschema/scripts/gen_format_data.py
"""
import importlib.metadata
import json
import os
import random
import re

import rfc3986_validator
import rfc3987_syntax
from rfc3987_syntax import is_valid_syntax
from webcolors import _definitions

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "internal", "formats", "data.mbt")


def lit(s):
    return json.dumps(s, ensure_ascii=True)


# --- lark grammar to regex ------------------------------------------------

TOKEN = re.compile(
    r'\s*(?:(?P<arrow>->\s*\w+)|(?P<str>"(?:[^"\\]|\\.)*")|(?P<re>/(?:[^/\\]|\\.)*/)'
    r'|(?P<name>\w+)|(?P<range>\.\.)|(?P<op>[|()?*+]))'
)


def tokenize(body):
    pos, out = 0, []
    body = body.strip()
    while pos < len(body):
        m = TOKEN.match(body, pos)
        if not m:
            raise ValueError(f"cannot tokenize {body[pos:]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind != "arrow":
            out.append((kind, m.group(kind)))
    return out


def load_rules(text):
    rules, current = {}, None
    for line in text.splitlines():
        if not line.strip():
            continue
        m = re.match(r"^(\w+)\s*:(.*)$", line)
        if m and not line.startswith(" "):
            current = m.group(1)
            rules[current] = m.group(2)
        else:
            rules[current] += " " + line.strip()
    return {name: tokenize(body) for name, body in rules.items()}


def to_regex(rules):
    memo = {}

    def rule(name):
        if name not in memo:
            memo[name] = "(?:" + expr(list(rules[name])) + ")"
        return memo[name]

    def expr(tokens):
        alts, seq, stack = [], [], []
        i = 0

        def atom_at(i):
            kind, value = tokens[i]
            if kind == "op" and value == "(":
                depth, j = 0, i
                while True:
                    if tokens[j] == ("op", "("):
                        depth += 1
                    elif tokens[j] == ("op", ")"):
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                return "(?:" + expr(tokens[i + 1:j]) + ")", j + 1
            if kind == "str":
                s = json.loads(value)
                if i + 2 < len(tokens) and tokens[i + 1] == ("range", ".."):
                    t = json.loads(tokens[i + 2][1])
                    return f"[{re.escape(s)}-{re.escape(t)}]", i + 3
                return "(?:" + re.escape(s) + ")", i + 1
            if kind == "re":
                return value[1:-1], i + 1
            if kind == "name":
                return rule(value), i + 1
            raise ValueError(f"unexpected {value!r}")

        while i < len(tokens):
            if tokens[i] == ("op", "|"):
                alts.append("".join(seq))
                seq = []
                i += 1
                continue
            atom, i = atom_at(i)
            if i < len(tokens) and tokens[i][0] == "op" and tokens[i][1] in "?*+":
                atom = "(?:" + atom + ")" + tokens[i][1]
                i += 1
            seq.append(atom)
        alts.append("".join(seq))
        return "|".join(alts)

    return rule


def check(term, pattern, samples):
    compiled = re.compile(pattern)
    for s in samples:
        expected = is_valid_syntax(term, s)
        got = compiled.fullmatch(s) is not None
        if expected != got:
            raise AssertionError(f"{term}: {s!r}: grammar {expected}, regex {got}")


def samples():
    seeds = ["http://example.com/a/b?c=d#e", "http://[2001:db8::7]/", "//a@b:1/c",
             "urn:isbn:0451450523", "\u00e9x:\u00e9?\ue000#f", "a/b/c", "?q", "#f",
             "http://1.2.3.4:80", "http://[v1.x]/", "../x", "x:y%41%zz", "",
             "http://[1:2:3:4:5:6:7:8]/", "http://[::1:2:3:4:5:6]", "http://255.255.255.256"]
    alphabet = list("ab09:/?#[]@!$&'()*+,;=%-._~ \u00e9\ue000\ufffd\U0001F600v.") + ["::", "//", "25", "%4"]
    rng = random.Random(3987)
    out = set(seeds)
    for _ in range(20000):
        s = list(rng.choice(seeds))
        for _ in range(rng.randint(1, 4)):
            op = rng.random()
            if op < 0.4 and s:
                del s[rng.randrange(len(s))]
            elif op < 0.8:
                s.insert(rng.randint(0, len(s)), rng.choice(alphabet))
            elif s:
                s[rng.randrange(len(s))] = rng.choice(alphabet)
        out.add("".join(s))
    return sorted(out)


def main():
    grammar_path = os.path.join(os.path.dirname(rfc3987_syntax.__file__), "syntax_rfc3987.lark")
    with open(grammar_path, encoding="utf-8") as f:
        rule = to_regex(load_rules(f.read()))
    iri, iri_reference = rule("iri"), rule("iri_reference")
    data = samples()
    check("iri", iri, data)
    check("iri_reference", iri_reference, data)

    versions = {
        name: importlib.metadata.version(name)
        for name in ["rfc3986-validator", "rfc3987-syntax", "webcolors"]
    }
    lines = [
        "// Code generated by jsonschema/scripts/gen_format_data.py. DO NOT EDIT.",
        "// " + "; ".join(f"{k} {v}" for k, v in versions.items()) + ".",
        "",
        "///|",
        "/// `rfc3986_validator.URI_RE_COMP` (Python `re` syntax, MIT-licensed",
        "/// rfc3986-validator by Nicolas Aimetti).",
        f"let rfc3986_uri_pattern : String = {lit('(?x)' + rfc3986_validator.URI_RE_COMP.pattern)}",
        "",
        "///|",
        "/// `rfc3986_validator.URI_REF_RE_COMP` (Python `re` syntax).",
        f"let rfc3986_uri_reference_pattern : String = {lit('(?x)' + rfc3986_validator.URI_REF_RE_COMP.pattern)}",
        "",
        "///|",
        "/// The `iri` rule of rfc3987-syntax's grammar (MIT, Will Riley) as a",
        "/// Python regex, to be matched against the whole string.",
        f"let rfc3987_syntax_iri_pattern : String = {lit(chr(92) + 'A(?:' + iri + ')' + chr(92) + 'Z')}",
        "",
        "///|",
        "/// The `iri_reference` rule of rfc3987-syntax's grammar as a Python regex.",
        f"let rfc3987_syntax_iri_reference_pattern : String = {lit(chr(92) + 'A(?:' + iri_reference + ')' + chr(92) + 'Z')}",
        "",
    ]
    names = sorted(_definitions._names_to_hex["css3"])
    lines += [
        "///|",
        "/// The CSS3 color names known to `webcolors.name_to_hex`.",
        "let css3_color_names : Array[String] = [",
    ]
    for n in names:
        lines.append(f"  {lit(n)},")
    lines += ["]", ""]
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
