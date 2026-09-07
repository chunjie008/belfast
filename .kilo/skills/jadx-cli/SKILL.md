---
name: jadx-cli
description: Decompile Android APK and DEX files with the installed jadx command-line tools.
---

# JADX CLI

Use the Linux jadx CLI installed at `~/.local/tools/jadx/bin/jadx`.
The command aliases `jadx` and `jadx-gui` are available through `~/.local/bin`.

## When to use

Use this skill when the user wants to:

- Decompile an Android APK or DEX file.
- Export Java source code from an APK.
- Extract APK resources without decompiling source.
- Choose separate output directories for source and resources.
- Inspect jadx CLI options or version.

## Basic commands

Check availability:

```bash
jadx --version
jadx --help
```

Decompile an APK or DEX file into one output directory:

```bash
jadx -d output app.apk
```

Use an explicit executable path when the shell has not loaded the user PATH:

```bash
~/.local/tools/jadx/bin/jadx -d output app.apk
```

## Output control

Export Java source and resources to separate directories:

```bash
jadx -ds sources -dr resources app.apk
```

Export only Java source:

```bash
jadx --no-res -d sources app.apk
```

Export only resources:

```bash
jadx --no-src -d resources app.apk
```

## Operating rules

- Treat the input APK or DEX path as user data; do not overwrite it.
- Prefer a new, explicit output directory for each analysis.
- Preserve the original input file and report the output directory after completion.
- Run `jadx --help` when an option is uncertain instead of guessing.
- For multiple inputs, pass them together only when a shared output directory is intended.
- Use `jadx-gui` only when the user explicitly needs the graphical interface.
- Do not claim that obfuscated or missing code was recovered; report jadx warnings and failures.

## Common workflow

1. Confirm the input file exists and identify whether it is APK or DEX.
2. Choose a non-conflicting output directory.
3. Run `jadx -d <output-directory> <input-file>`.
4. Check the command result and warnings.
5. Report the output directory and any files that could not be decoded.
