# Sensify

A compiled DSL for IoT edge stream processing.

## Overview

Sensify lets developers define optimized data-filtering and aggregation pipelines for resource-constrained IoT devices such as Raspberry Pi and industrial gateways. It compiles to native performance via LLVM JIT and supports hot-swapping rules on running devices.

## Features

- Pipeline syntax (`|>`)
- Stateful sliding windows
- Sandboxed by design
- JIT hot-swapping
- No file I/O, deep recursion, or dynamic memory allocation

## Architecture

1. **Lexer:** Flex
2. **Parser:** Bison
3. **IR & Codegen:** LLVM JIT

## Example

```sensify
sensor temp_stream = input(8080);
endpoint cloud_alert = output("https://api.factory.com/alert");

pipeline ThermalMonitor {
    ingest temp_stream
    |> average_window(15)
    |> filter(value > 65.5)
    |> trigger(cloud_alert, "Critical Overheating Detected");
}
```

## Implementation Plan

- **Phase 1:** Flex/Bison grammar + AST
- **Phase 2:** C++ semantic analyzer
- **Phase 3:** LLVM Core + JIT runtime

## Status

In development.