# Compiler Construction Project: Sensify Usage Manual

This manual explains how to build and run the Sensify project on Windows using Docker, Ubuntu/WSL2, and macOS. Follow the section for your operating system and run the commands in the order shown.

## Project Team

| Name | Roll Number |
|---|---|
| Abdul Rehman | 23-0787 |
| Muhammad Fakhir | 22L-6827 |
| Danyal Rehman | 22L-6576 |

## 1. Windows (using Docker)

### Step 1: Open the project folder

Open PowerShell and change to the root directory of the `Sensify` project. This directory should contain the `Dockerfile`, `phase1_interpreter`, `phase2_compiler`, and `examples` folders.

### Step 2: Build the Docker image

```powershell
docker build -t sensify-env .
```

This builds a Docker image named `sensify-env` using the instructions in the project's Dockerfile.

### Step 3: Start the container

```powershell
docker run -it --rm -v ${PWD}:/work sensify-env
```

This starts the container and makes the current project directory available inside it at `/work`. The `--rm` option removes the container when you exit it; your project files remain in the mounted folder.

### Step 4: Build and run Phase 1

Run these commands inside the container:

```bash
cd /work/phase1_interpreter
make
./sensify ../examples/thermal.sfy ../examples/thermalReadings.txt
```

### Step 5: Build and run Phase 2

```bash
cd /work/phase2_compiler
make
./compileSensify.sh ../examples/thermal.sfy thermal
./thermal < ../examples/thermalReadings.txt
```

The compiler script generates a native executable named `thermal`, which is then run with the thermal readings as standard input.

### Optional: Run all tests

Return to the project root and run:

```bash
cd /work
chmod +x runTests.sh
./runTests.sh
```

If the Docker image does not already include the required tools, install them inside the container:

```bash
apt-get update
apt-get install -y flex bison gcc make clang
```

## 2. Ubuntu / WSL2

### Step 1: Open the project folder

Open a terminal and move to the root directory of the `Sensify` project.

### Step 2: Update package information

```bash
sudo apt-get update
```

This refreshes the package information used by Ubuntu's package manager.

### Step 3: Install the required tools

```bash
sudo apt-get install -y flex bison gcc make clang
```

These packages provide the lexer generator, parser generator, C compiler, build utility, and LLVM compiler needed by the project.

### Step 4: Build and run Phase 1

```bash
cd phase1_interpreter
make
./sensify ../examples/factory.sfy ../examples/factoryReadings.txt
```

### Step 5: Build and run Phase 2

```bash
cd ../phase2_compiler
make
./compileSensify.sh ../examples/factory.sfy factory
./factory < ../examples/factoryReadings.txt
```

### Optional: Run all tests

Return to the project root and run:

```bash
cd ..
chmod +x runTests.sh
./runTests.sh
```

## 3. macOS

### Step 1: Open the project folder

Open Terminal and move to the root directory of the `Sensify` project.

### Step 2: Install or update Homebrew

If Homebrew is already installed, update it:

```bash
brew update
```

If Homebrew is not installed, follow the installation instructions on the official Homebrew website: https://brew.sh/

### Step 3: Install the required tools

```bash
brew install flex bison gcc make llvm
```

The project uses Flex, Bison, GCC, Make, and Clang. The Homebrew LLVM package provides Clang.

### Step 4: Add the Homebrew tools to PATH

Run this command in the current Terminal session:

```bash
export PATH="$(brew --prefix flex)/bin:$(brew --prefix bison)/bin:$(brew --prefix llvm)/bin:$PATH"
```

To make this setting available in future Terminal sessions, add the same `export PATH=...` line to your shell configuration file (usually `~/.zshrc` on modern macOS), then open a new terminal.

### Step 5: Check the installations

```bash
flex --version
bison --version
gcc --version
make --version
clang --version
```

If macOS reports that developer tools are missing, install the Xcode Command Line Tools:

```bash
xcode-select --install
```

### Step 6: Build and run Phase 1

```bash
cd phase1_interpreter
make
./sensify ../examples/thermal.sfy ../examples/thermalReadings.txt
```

### Step 7: Build and run Phase 2

```bash
cd ../phase2_compiler
make
./compileSensify.sh ../examples/thermal.sfy thermal
./thermal < ../examples/thermalReadings.txt
```

### Optional: Run all tests

Return to the project root and run:

```bash
cd ..
chmod +x runTests.sh
./runTests.sh
```

## 4. Understanding the Test Script

The `runTests.sh` script automates the main project checks. It builds the interpreter and compiler, runs the supplied example programs, compares program output with the expected output files, and checks that invalid programs are rejected.

When all supplied checks pass, the expected summary is:

```text
Passed: 10   Failed: 0
```

If a test fails, read the error printed in the terminal. Check that the required tools are installed, that you are running the script from the project root, and that the source and example files are present.

## 5. Before Submission

Before creating the final ZIP file, check the project directory and remove generated build files if your instructor requires a source-only submission. Common generated files include:

- `lex.yy.c`
- `sensify.tab.c`
- `sensify.tab.h`
- Compiled executables such as `sensify`, `sensifyc`, `thermal`, and `factory`

Keep the original source files, Makefiles, shell scripts, examples, expected output files, and documentation. Place `README.pdf` and `USAGE_MANUAL.pdf` in the root of the `Sensify` folder alongside the source folders.

Finally, compress the complete `Sensify` folder into a ZIP archive and submit it through your university portal. Always follow any additional file-format or submission instructions provided by your instructor.
