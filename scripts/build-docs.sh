#!/usr/bin/env bash
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
#
# Build the sheet in `docs/`: the engine the front plate runs, the reference that is
# generated from the interfaces, and the version the footer prints. The engine is a
# build product and is not in the repository; the other two are committed and checked.
#
#   scripts/build-docs.sh
#   git diff --exit-code docs/api.html docs/version.js
set -euo pipefail

cd "$(dirname "$0")/.."

moon build --target js --release src/examples/03-browser
mkdir -p docs/engine
cp _build/js/release/build/examples/03-browser/03-browser.js docs/engine/moonp8s.js

python3 scripts/gen_api.py
python3 scripts/gen_version.py
