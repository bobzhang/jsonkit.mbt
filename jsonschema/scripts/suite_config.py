"""
The test classes of upstream's ``test_jsonschema_test_suite.py``: for each,
the (suite version, file) groups it runs, the validator, whether a format
checker is passed, and which skip function applies.

Shared by ``suite_oracle.py`` and ``gen_suite.py``.
"""
import os

SUITE = os.environ.get(
    "JSON_SCHEMA_TEST_SUITE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "..", "..", "upstream", "JSON-Schema-Test-Suite"),
)


def _glob(version, sub):
    d = os.path.join(SUITE, "tests", version, sub)
    return sorted(
        (version, os.path.join(sub, f) if sub else f)
        for f in os.listdir(d) if f.endswith(".json")
    )


def cases(version):
    return _glob(version, "")


def format_cases(version):
    return _glob(version, "optional/format")


def optional(version, name):
    return [(version, f"optional/{name}.json")]


def configs():
    """(class name, groups, validator, use format checker, skip name)"""
    d3, d4, d6, d7 = "draft3", "draft4", "draft6", "draft7"
    d19, d20 = "draft2019-09", "draft2020-12"
    return [
        ("TestDraft3",
         cases(d3) + format_cases(d3) + optional(d3, "bignum")
         + optional(d3, "non-bmp-regex") + optional(d3, "zeroTerminatedFloats"),
         "Draft3Validator", True, "draft3"),
        ("TestDraft4",
         cases(d4) + format_cases(d4) + optional(d4, "bignum")
         + optional(d4, "float-overflow") + optional(d4, "id")
         + optional(d4, "non-bmp-regex") + optional(d4, "zeroTerminatedFloats"),
         "Draft4Validator", True, "draft4"),
        ("TestDraft6",
         cases(d6) + format_cases(d6) + optional(d6, "bignum")
         + optional(d6, "float-overflow") + optional(d6, "id")
         + optional(d6, "non-bmp-regex"),
         "Draft6Validator", True, "draft6"),
        ("TestDraft7",
         cases(d7) + format_cases(d7) + optional(d7, "bignum")
         + optional(d7, "cross-draft") + optional(d7, "float-overflow")
         + optional(d6, "id") + optional(d7, "non-bmp-regex")
         + optional(d7, "unknownKeyword"),
         "Draft7Validator", True, "draft7"),
        ("TestDraft201909",
         cases(d19) + optional(d19, "anchor") + optional(d19, "bignum")
         + optional(d19, "cross-draft") + optional(d19, "float-overflow")
         + optional(d19, "id") + optional(d19, "no-schema")
         + optional(d19, "non-bmp-regex")
         + optional(d19, "refOfUnknownKeyword")
         + optional(d19, "unknownKeyword"),
         "Draft201909Validator", False, "draft201909"),
        ("TestDraft201909Format", format_cases(d19),
         "Draft201909Validator", True, "draft201909format"),
        ("TestDraft202012",
         cases(d20) + optional(d19, "anchor") + optional(d20, "bignum")
         + optional(d20, "cross-draft") + optional(d20, "float-overflow")
         + optional(d20, "id") + optional(d20, "no-schema")
         + optional(d20, "non-bmp-regex")
         + optional(d20, "refOfUnknownKeyword")
         + optional(d20, "unknownKeyword"),
         "Draft202012Validator", False, "draft202012"),
        ("TestDraft202012Format", format_cases(d20),
         "Draft202012Validator", True, "draft202012format"),
    ]
