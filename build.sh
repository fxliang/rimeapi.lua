#!/bin/bash
LIBRIME=$(whereis librime.so | cut -d: -f2- | xargs -n1 | head -n1)
if [[ -z "$LIBRIME" ]]; then
    echo "librime.so not found in system, please install librime first"
    exit 1
fi
LUALIB=$(objdump -p "$LIBRIME" 2>/dev/null | awk '/NEEDED.*lua/ {print $2}')
echo $LUALIB

if [[ -z "$LUALIB" || "$LUALIB" == *"luajit"* ]]; then
    if [[ -z "$LUALIB" ]]; then
        echo "librime does not depend on standard lua/luajit"
    else
        echo "librime depends on luajit"
    fi
    echo "building rimeapi.so and rimeapi.app with luajit as default lua engine"
    echo
    xmake f --lua_engine=luajit
    xmake
    exit 0
# else if librime depends on standard lua
else
    echo "librime depends on standard lua"
    echo "building rimeapi.so and rimeapi.app with standard lua as default lua engine"
    echo
    xmake f --lua_engine=lua
    xmake -v
    exit 0
fi