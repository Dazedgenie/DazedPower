#!/bin/sh
# Runs the headless checks. Needs a Lua 5.3+ interpreter on PATH as `lua`, and DazedCore beside this mod.
cd "$(dirname "$0")" || exit 1
rc=0
lua syntax_check.lua ../../common/media/lua || rc=1
lua load_test.lua || rc=1
exit $rc
