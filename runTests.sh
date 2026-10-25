#!/bin/bash
# Builds both phases and checks every example.   Usage: ./runTests.sh
cd "$(dirname "$0")"
passed=0
failed=0

check() {   # check "test name" exitCode(0 = ok)
    if [ "$2" -eq 0 ]; then echo "PASS  $1"; passed=$((passed + 1));
    else echo "FAIL  $1"; failed=$((failed + 1)); fi
}

make -C phase1_interpreter > /dev/null 2>&1 || { echo "Phase 1 build failed"; exit 1; }
make -C phase2_compiler    > /dev/null 2>&1 || { echo "Phase 2 build failed"; exit 1; }
mkdir -p build

for name in thermal factory; do
    # Phase 1: interpreter
    phase1_interpreter/sensify examples/$name.sfy examples/${name}Readings.txt > build/$name.interp.txt
    diff -q build/$name.interp.txt expected/$name.expected.txt > /dev/null
    check "phase 1 interpreter: $name" $?

    # Phase 2: compiler -> IR -> executable
    phase2_compiler/compileSensify.sh examples/$name.sfy build/$name > /dev/null 2>&1
    build/$name < examples/${name}Readings.txt > build/$name.compiled.txt
    diff -q build/$name.compiled.txt expected/$name.expected.txt > /dev/null
    check "phase 2 compiler:    $name" $?
done

# wrong programs must be rejected (exit code 1)
for name in errorUndeclared errorNoSink errorSyntax; do
    phase1_interpreter/sensify examples/$name.sfy < /dev/null > /dev/null 2>&1
    [ $? -eq 1 ]; check "phase 1 rejects $name" $?
    phase2_compiler/sensifyc examples/$name.sfy build/$name.ll > /dev/null 2>&1
    [ $? -eq 1 ]; check "phase 2 rejects $name" $?
done

echo "Passed: $passed   Failed: $failed"
[ $failed -eq 0 ]
