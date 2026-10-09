#!/bin/sh
# Runs the headless checks. Needs a Lua 5.3+ interpreter on PATH as `lua`.
# Usage: sh tools/tests/run_all.sh [<DazedCore lua root>]; DAZEDCORE_LUA works too. The default is the sibling
# repo layout: ../dazedcore/Contents/mods/DazedCore/common/media/lua beside this repo.
cd "$(dirname "$0")" || exit 1
ROOT=../../Contents/mods/DazedPower/common/media/lua
CORE=${1:-${DAZEDCORE_LUA:-../../../dazedcore/Contents/mods/DazedCore/common/media/lua}}
rc=0
lua syntax_check.lua "$ROOT" || rc=1
lua load_test.lua "$ROOT" "$CORE" || rc=1
exit $rc
