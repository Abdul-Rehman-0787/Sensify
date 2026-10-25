#!/bin/bash
# Usage: ./compileSensify.sh program.sfy [outputName]
# Step 1: sensifyc turns program.sfy into LLVM IR (outputName.ll)
# Step 2: clang turns the IR into a native executable (outputName)
if [ -z "$1" ]; then
    echo "Usage: $0 program.sfy [outputName]"
    exit 1
fi
here="$(cd "$(dirname "$0")" && pwd)"
name="${2:-$(basename "$1" .sfy)}"
"$here/sensifyc" "$1" "$name.ll" || exit 1
clang -O2 -Wno-override-module "$name.ll" -o "$name" || exit 1
echo "Built executable: $name   (run it with:  $name < readings.txt)"
