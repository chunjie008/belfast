---
name: ghidra-headless
description: Analyze binaries with the installed Ghidra 12.1.3 headless analyzer.
---

# Ghidra Headless

Use the Linux Ghidra 12.1.3 installation at `~/.local/tools/ghidra/ghidra_12.1.3_PUBLIC`.
The headless launcher is:

```bash
~/.local/tools/ghidra/ghidra_12.1.3_PUBLIC/support/analyzeHeadless
```

Ghidra requires Java 21 or a compatible supported JDK. Headless analysis does not require a graphical desktop.

## When to use

Use this skill when the user wants to:

- Import and analyze an executable, firmware image, library, object file, or other binary.
- Run Ghidra analysis without opening the GUI.
- Apply a Ghidra script or script directory in a repeatable batch job.
- Export analysis results from a Ghidra project.
- Process several binaries in an automated workflow.

## Check availability

```bash
java -version
~/.local/tools/ghidra/ghidra_12.1.3_PUBLIC/support/analyzeHeadless 2>&1 | head -n 20
```

The command aliases `ghidra` and `il2cppinspector` are separate tools; use the explicit `analyzeHeadless` path for headless Ghidra work unless a dedicated alias has been configured.

## Core command shape

```bash
analyzeHeadless <project-directory> <project-name> [options] [<input-file> ...]
```

With the installed copy:

```bash
~/.local/tools/ghidra/ghidra_12.1.3_PUBLIC/support/analyzeHeadless \
  <project-directory> <project-name> \
  -import <input-file>
```

Ghidra creates or opens the project under `<project-directory>`. Use a new project name for an independent analysis.

## Common workflows

Create a project, import a binary, and run the default analyzers:

```bash
analyzeHeadless work ghidra-analysis \
  -import ./sample.bin
```

Import into an existing project and overwrite the existing program version:

```bash
analyzeHeadless work ghidra-analysis \
  -process sample.bin \
  -overwrite
```

Analyze without importing a new file:

```bash
analyzeHeadless work ghidra-analysis \
  -process sample.bin
```

Use a named processor and language when automatic detection is insufficient:

```bash
analyzeHeadless work ghidra-analysis \
  -import ./sample.bin \
  -processor "x86:LE:64:default"
```

Run a script from a script directory:

```bash
analyzeHeadless work ghidra-analysis \
  -process sample.bin \
  -scriptPath ./ghidra-scripts \
  -postScript ExportFunctions.java
```

Run a pre-script and post-script:

```bash
analyzeHeadless work ghidra-analysis \
  -import ./sample.bin \
  -preScript Prepare.java \
  -postScript ExportResults.java
```

Process every file in an input directory:

```bash
analyzeHeadless work ghidra-analysis \
  -import ./samples
```

## Useful options

- `-import <file-or-directory>` imports one file or a directory of files.
- `-process <program>` processes an item already in the project.
- `-recursive` recursively imports or processes directory contents.
- `-overwrite` replaces an existing program during import.
- `-deleteProject` deletes the project after processing; use only for temporary projects.
- `-scriptPath <directory>` adds a directory to the Ghidra script search path.
- `-preScript <script> [args...]` runs a script before analysis.
- `-postScript <script> [args...]` runs a script after analysis.
- `-noanalysis` skips automatic analysis.
- `-analysisTimeoutPerFile <seconds>` limits analysis time per file.
- `-log <file>` writes the launcher log to a specified file.
- `-scriptlog <file>` writes script output to a specified file.
- `-analysisProperties <file>` loads analyzer property settings.
- `-max-cpu <n>` limits the number of analysis worker threads.

Check the exact options supported by this Ghidra release before using less common flags:

```bash
analyzeHeadless -h
```

## Operating rules

- Treat binaries and firmware as user data; never modify the original input.
- Use a dedicated project directory and project name for each unrelated analysis.
- Do not use `-deleteProject` when the user expects to inspect the project later.
- Use `-overwrite` only when replacing a known previous import is intended.
- Prefer `-log` and `-scriptlog` for batch jobs so failures remain inspectable.
- Keep scripts and generated output in separate directories.
- Report analyzer errors, import failures, timeouts, and skipped files; do not describe a binary as fully analyzed when the command reported failures.
- Do not use `ghidraRun` for headless jobs.

## Common workflow

1. Confirm the input path exists and select a non-conflicting project directory.
2. Run `analyzeHeadless -h` if an option or processor language is uncertain.
3. Import or process the input with an explicit project name.
4. Review the exit status and launcher/script logs.
5. Report the project directory and any failed, skipped, or timed-out inputs.
