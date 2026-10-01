#!/usr/bin/env python3
"""
Record how upstream python-jsonschema (with its ``format-nongpl`` extras
installed, i.e. without the GPL ``rfc3987`` package)
fares on each JSON-Schema-Test-Suite test, mirroring the test classes of
upstream's ``jsonschema/tests/test_jsonschema_test_suite.py``.

The result (``suite_oracle.json``) is consumed by ``gen_suite.py``: each
generated MoonBit test knows upstream's outcome (valid / invalid / error)
and whether upstream skips it, so the port is held to *upstream's*
behaviour, including the cases where upstream disagrees with the suite.

Usage (needs upstream jsonschema importable, plus referencing,
jsonschema-specifications and the ``format-nongpl`` extras -- fqdn, idna,
isoduration, jsonpointer, rfc3339-validator, rfc3986-validator,
rfc3987-syntax, uri-template, webcolors -- but *not* rfc3987):

    JSON_SCHEMA_TEST_SUITE=upstream/JSON-Schema-Test-Suite \\
    PYTHONPATH=upstream/jsonschema python jsonschema/scripts/suite_oracle.py
"""
import json
import os
import sys

import jsonschema
from jsonschema.tests import test_jsonschema_test_suite as t
from jsonschema.tests._suite import Suite

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "suite_oracle.json")

sys.path.insert(0, HERE)
from suite_config import configs  # noqa: E402


def main():
    suite = Suite()
    out = {}
    for cls_name, groups, validator_name, use_format, skip_name in configs():
        Validator = getattr(jsonschema, validator_name)
        skip = getattr(t, "_oracle_skip_" + cls_name, None) or SKIPS[skip_name]
        for version_name, rel in groups:
            version = suite.version(name=version_name)
            path = version._path / rel
            cases = list(version._cases_in(paths=[path]))
            results = []
            for case in cases:
                row = []
                for test in case.tests:
                    reason = skip(test)
                    kwargs = {}
                    if use_format:
                        kwargs["format_checker"] = Validator.FORMAT_CHECKER
                    try:
                        test.validate(Validator=Validator, **kwargs)
                        outcome = "v"
                    except jsonschema.ValidationError:
                        outcome = "i"
                    except Exception as e:  # noqa: BLE001
                        outcome = "e:" + type(e).__name__
                    row.append([outcome, reason])
                results.append(row)
            out[f"{cls_name}|{version_name}/{rel}"] = results
    with open(OUT, "w") as f:
        json.dump(out, f, indent=0, sort_keys=True)
    print(f"wrote {OUT}", file=sys.stderr)


SKIPS = {
    "draft3": lambda test: (
        t.ecmascript_regex(test)
        or t.missing_format(jsonschema.Draft3Validator)(test)
        or t.complex_email_validation(test)
    ),
    "draft4": lambda test: (
        t.ecmascript_regex(test)
        or t.leap_second(test)
        or t.missing_format(jsonschema.Draft4Validator)(test)
        or t.complex_email_validation(test)
        or t.hostname_validation(test)
    ),
    "draft6": lambda test: (
        t.ecmascript_regex(test)
        or t.leap_second(test)
        or t.missing_format(jsonschema.Draft6Validator)(test)
        or t.complex_email_validation(test)
        or t.hostname_validation(test)
    ),
    "draft7": lambda test: (
        t.ecmascript_regex(test)
        or t.leap_second(test)
        or t.missing_format(jsonschema.Draft7Validator)(test)
        or t.complex_email_validation(test)
        or t.hostname_validation(test)
        or t.idn_hostname_validation(test)
    ),
    "draft201909": t.skip(
        message="Vocabulary support is still in-progress.",
        subject="vocabulary",
        description="no validation: invalid number, but it still validates",
    ),
    "draft201909format": lambda test: (
        t.complex_email_validation(test)
        or t.hostname_validation(test)
        or t.idn_hostname_validation(test)
        or t.ecmascript_regex(test)
        or t.leap_second(test)
        or t.missing_format(jsonschema.Draft201909Validator)(test)
        or t.duration_validation(test)
    ),
    "draft202012": lambda test: (
        t.skip(
            message="Vocabulary support is still in-progress.",
            subject="vocabulary",
            description="no validation: invalid number, but it still validates",
        )(test)
        or t.unicode_property_escape(test)
    ),
    "draft202012format": lambda test: (
        t.complex_email_validation(test)
        or t.hostname_validation(test)
        or t.idn_hostname_validation(test)
        or t.ecmascript_regex(test)
        or t.leap_second(test)
        or t.missing_format(jsonschema.Draft202012Validator)(test)
        or t.duration_validation(test)
    ),
}


if __name__ == "__main__":
    main()
