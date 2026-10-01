#!/bin/sh
# Clone the upstream sources this workspace was ported from, pinned to the
# exact commits used, into ./upstream (git-ignored). The generator scripts in
# each module's scripts/ directory read fixtures from there.
set -e
cd "$(dirname "$0")/.."
mkdir -p upstream
fetch() {
  name=$1 url=$2 rev=$3
  if [ ! -d "upstream/$name" ]; then
    git clone --quiet "$url" "upstream/$name"
  fi
  git -C "upstream/$name" fetch --quiet --depth 1 origin "$rev" 2>/dev/null || true
  git -C "upstream/$name" checkout --quiet "$rev"
  echo "upstream/$name @ $rev"
}
fetch jsonschema https://github.com/python-jsonschema/jsonschema 51cd75e
fetch referencing https://github.com/python-jsonschema/referencing 80895e5
fetch jsonschema-specifications https://github.com/python-jsonschema/jsonschema-specifications 7319b3c
fetch JSON-Schema-Test-Suite https://github.com/json-schema-org/JSON-Schema-Test-Suite 5b0ee16
fetch referencing-suite https://github.com/python-jsonschema/referencing-suite a13bcf6
fetch jmespath.py https://github.com/jmespath/jmespath.py 2812594
