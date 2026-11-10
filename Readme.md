# Sensify

**Compiler Construction Project — Phase 1: Interpreter | Phase 2: Ahead-of-Time (AOT) Compiler**

## Project Team

| Name | Roll Number |
|---|---|
| Abdul Rehman | 23-0787 |
| Muhammad Fakhir | 22L-6827 |
| Danyal Rehman | 22L-6576 |

Sensify is a small domain-specific language (DSL) designed for IoT edge-stream processing. A Sensify program declares input sensors and output endpoints, then defines pipelines that process incoming values. Each pipeline starts with a sensor, applies one or more processing stages using the `|>` operator, and finishes with an output stage.

This project includes two implementations of the language:

- **Phase 1 — Interpreter:** reads a Sensify program and executes it directly.
- **Phase 2 — AOT Compiler:** translates a Sensify program into LLVM intermediate representation (IR), then uses Clang to create a native executable.

## 1. Requirements and Installation

The project is intended to run on Linux. It has been tested on Ubuntu 24.04 with Clang 18, Flex 2.6, and Bison 3.8.

### Required tools

| Tool | Used for |
|---|---|
| Flex | Generates the lexical analyser |
| Bison | Generates the parser |
| GCC | Compiles the Phase 1 interpreter and supporting C code |
| Make | Runs the project build instructions |
| Clang | Compiles the LLVM IR produced in Phase 2 |

Phase 1 requires Flex, Bison, GCC, and Make. Phase 2 also requires Clang.

### Ubuntu / WSL2

Open a terminal and install the required packages:

```bash
sudo apt-get update
sudo apt-get install -y flex bison gcc make clang
```

### Windows (using Docker)

Build the supplied Docker image from the root of the project:

```powershell
docker build -t sensify-env .
docker run -it --rm -v ${PWD}:/work sensify-env
```

The second command starts the container and mounts the project folder at `/work`. Run the build and execution commands from inside the container. The Docker image should contain the required build tools; if it does not, install them inside the container:

```bash
apt-get update
apt-get install -y flex bison gcc make clang
```

### macOS

Install Homebrew first if it is not already available. Then install the compiler tools:

```bash
brew update
brew install flex bison gcc make llvm
```

Add the Homebrew tools to your `PATH` for the current terminal session:

```bash
export PATH="$(brew --prefix flex)/bin:$(brew --prefix bison)/bin:$(brew --prefix llvm)/bin:$PATH"
```

Check that the tools are available:

```bash
flex --version
bison --version
gcc --version
make --version
clang --version
```

If the commands are not found, open a new terminal and check your Homebrew installation and `PATH`. On macOS, the system may also require the Xcode Command Line Tools:

```bash
xcode-select --install
```

## 2. Building and Running the Project

Run these commands from the root directory of the Sensify project unless stated otherwise.

### Phase 1: Interpreter

```bash
cd phase1_interpreter
make
./sensify ../examples/thermal.sfy ../examples/thermalReadings.txt
```

The `make` command builds the interpreter. The final command runs it using the thermal example program and its input readings.

### Phase 2: AOT Compiler

From the project root, run:

```bash
cd phase2_compiler
make
./compileSensify.sh ../examples/thermal.sfy thermal
./thermal < ../examples/thermalReadings.txt
```

The helper script runs the Sensify compiler and Clang to create a native executable named `thermal`. The last command supplies the readings through standard input.

For the same program and input readings, the interpreter and compiled executable are expected to produce the same output.

## 3. The Sensify Language

### Basic program structure

```sensify
// A comment
sensor sensorName = input(port);
endpoint endpointName = output("https://example.com/alert");

pipeline PipelineName {
    ingest sensorName
    |> stage
    |> stage
    |> sink;
}
```

A program can declare sensors and endpoints before defining pipelines. A pipeline begins with `ingest`, passes values through stages connected by `|>`, and ends with a sink. The final sink is followed by a semicolon.

### Supported stages

| Stage | Purpose |
|---|---|
| `averageWindow(n)` | Maintains a window of the latest `n` values and outputs their average. |
| `sumWindow(n)` | Maintains a window of the latest `n` values and outputs their sum. |
| `filter(condition)` | Allows a value to continue only when the condition is true. |
| `scale(x)` | Multiplies the current value by `x`. |
| `offset(x)` | Adds `x` to the current value. |
| `trigger(endpoint, "text")` | Ends a pipeline by printing an alert containing the endpoint, message, and value. |
| `emit()` | Ends a pipeline by printing the current value. |

A filter condition compares `value` with a number using `>`, `<`, `>=`, `<=`, `==`, or `!=`. Two comparisons may be joined with `&&` or `||`.

### Language rules

The compiler checks that names are declared before they are used and that every pipeline ends with a sink. Window sizes must be between 1 and 1000. Invalid programs report an error in the form `Error on line N` and exit with status code 1.

The language is intentionally limited: it does not provide file access, recursion, or dynamic memory allocation.

## 4. Example Programs

### 4.1 Thermal Monitor

```sensify
sensor temp_stream = input(8080);
endpoint cloud_alert = output("https://api.factory.com/alert");

pipeline ThermalMonitor {
    ingest temp_stream
    |> averageWindow(5)
    |> filter(value > 65.5)
    |> trigger(cloud_alert, "Critical Overheating Detected");
}
```

Example output:

```text
ALERT -> https://api.factory.com/alert : Critical Overheating Detected (value=66.60)
ALERT -> https://api.factory.com/alert : Critical Overheating Detected (value=73.30)
```

The exact output depends on the readings supplied to the program. The lines above are the documented example output for the provided thermal input.

### 4.2 Factory Monitor

```sensify
sensor pressure = input(9000);
sensor vibration = input(9001);
endpoint maintenance = output("https://api.factory.com/maintenance");

pipeline PressureWatch {
    ingest pressure
    |> sumWindow(3)
    |> scale(0.5)
    |> offset(-1)
    |> filter(value >= 10 && value <= 100)
    |> emit();
}

pipeline VibrationWatch {
    ingest vibration
    |> filter(value < 2 || value > 8)
    |> trigger(maintenance, "Abnormal vibration");
}
```

This example defines two independent pipelines. `PressureWatch` transforms pressure readings and emits values that pass its filter. `VibrationWatch` raises an alert when a vibration reading is below 2 or above 8.

## 5. Project Files

| File or folder | Description |
|---|---|
| `README.md` | Project overview, setup instructions, language reference, and examples. |
| `USAGE_MANUAL.md` | Step-by-step build and run instructions for Windows, Ubuntu/WSL2, and macOS. |
| `runTests.sh` | Builds both phases, runs the examples, and reports test results. |
| `examples/` | Sample Sensify programs and their input readings. |
| `expected/` | Expected output files used by the test script. |
| `phase1_interpreter/sensify.l` | Flex lexer for the interpreter. |
| `phase1_interpreter/sensify.y` | Bison grammar and C implementation for the interpreter. |
| `phase1_interpreter/Makefile` | Build instructions for Phase 1. |
| `phase2_compiler/sensify.l` | Flex lexer for the compiler. |
| `phase2_compiler/sensify.y` | Bison grammar and LLVM IR generation for Phase 2. |
| `phase2_compiler/Makefile` | Build instructions for Phase 2. |
| `phase2_compiler/compileSensify.sh` | Runs the compiler and Clang to create a native executable. |

## 6. Automated Testing

From the project root, run:

```bash
./runTests.sh
```

On systems where the script is not executable yet, run:

```bash
chmod +x runTests.sh
./runTests.sh
```

The script builds both phases, runs the examples through the interpreter and compiled executables, compares their output with the files in `expected/`, and checks that three invalid programs are rejected.

The expected final test summary is:

```text
Passed: 10   Failed: 0
```

This is the expected result when the project builds correctly and all supplied tests pass.

## 7. How Sensify Works

### 7.1 Phase 1: Flex and Bison Interpreter

Flex reads the source file character by character and groups the input into tokens, such as `PIPE`, `NUMBER`, and `IDENT`. Bison checks whether those tokens follow the language grammar.

When Bison recognises a grammar rule, its associated C action records the relevant information in tables for sensors, endpoints, and pipelines. After parsing is complete, `runAllPipelines()` processes the input readings and passes each value through the stages in the matching pipeline.

The interpreter executes the program directly. It does not generate an intermediate representation or a separate native executable.

### 7.2 Window Processing

A window stores up to `n` recent values in an array and tracks the position where the next value will be written. When the window is full, the new value replaces the oldest value.

The running total can be updated without recalculating the entire window:

```text
sum = sum + newValue - oldValue
```

For an average window, the current total is divided by the number of values currently stored. This approach avoids repeatedly looping through all values in the window.

### 7.3 Phase 2: Flex, Bison, and LLVM IR

Phase 2 uses the same language structure, but its grammar actions generate LLVM IR instead of executing the pipeline immediately.

Each pipeline is represented by a function such as `@pipeline_Name(double %value)`. Window state is stored in global variables. A filter generates a floating-point comparison (`fcmp`) and a conditional branch: values that fail the condition return early, while values that pass continue through the pipeline.

The `trigger` and `emit` sinks generate calls to `printf`. The compiler also generates a `main` function that reads values using `scanf` and calls the pipeline functions. Finally, Clang compiles the generated `.ll` file into a native executable.

## 8. Project Summary

Sensify demonstrates two ways to implement a small domain-specific language. The interpreter executes a parsed program directly, while the AOT compiler translates the program into LLVM IR and then into a native executable. Both phases support the same pipeline-oriented language and are tested against the supplied examples.
