---
name: metastringedit
description: Inspect, search, export, and modify string literals in Unity IL2CPP global-metadata.dat files with the metastringedit CLI.
---

# Meta String Edit

Use the installed `metastringedit` CLI to inspect and edit string literals in a Unity IL2CPP `global-metadata.dat` file.

## Installation

The package is installed in a dedicated virtual environment:

```bash
~/.local/venvs/metastringedit/bin/metastringedit
```

Installed version: `0.1.2`.

Use the absolute path in repeatable automation. If the shell has loaded the local user bin directory, the command may also be available as `metastringedit`.

Check availability:

```bash
~/.local/venvs/metastringedit/bin/metastringedit --version
~/.local/venvs/metastringedit/bin/metastringedit --help
```

## When to use

Use this skill when the user wants to:

- Inspect the metadata header and string table.
- Search string literals by case-insensitive text or regular expression.
- List strings by index, range, or page.
- Export string literals to JSON for programmatic processing.
- Replace string literals and write a patched metadata file.

This tool edits string literals only. It is not a general editor for IL2CPP type, method, field, parameter, or metadata table layouts.

## Basic commands

Set a shell variable to make commands easier to read:

```bash
METAEDIT="$HOME/.local/venvs/metastringedit/bin/metastringedit"
```

Show metadata information:

```bash
"$METAEDIT" ./global-metadata.dat --info
```

List strings:

```bash
# First 20 strings
"$METAEDIT" ./global-metadata.dat --list 0:20

# One string by index
"$METAEDIT" ./global-metadata.dat --list 12

# Inclusive index range
"$METAEDIT" ./global-metadata.dat --list 1-20
```

Search strings:

```bash
"$METAEDIT" ./global-metadata.dat --search "Player"
"$METAEDIT" ./global-metadata.dat --regex '^Player[0-9]+'
```

Export all strings to JSON:

```bash
"$METAEDIT" ./global-metadata.dat \
  --dump \
  --output ./metadata-strings.json
```

## Editing workflow

Always preserve the original file and write a new output file:

```bash
cp --reflink=auto ./global-metadata.dat ./global-metadata.dat.original

"$METAEDIT" ./global-metadata.dat \
  --edit '123=ModifiedName' \
  --output ./global-metadata.patched.dat
```

Multiple replacements can be supplied by repeating `--edit`:

```bash
"$METAEDIT" ./global-metadata.dat \
  --edit '123=ValueOne' \
  --edit '456=ValueTwo' \
  --output ./global-metadata.patched.dat
```

The edit syntax is `index=value`. First locate and verify each index with `--search` or `--list`, then apply the edit to a new output path. Quote values containing spaces or shell metacharacters.

After editing, inspect the resulting file and verify that the intended strings changed:

```bash
"$METAEDIT" ./global-metadata.patched.dat --info
"$METAEDIT" ./global-metadata.patched.dat --list 123
"$METAEDIT" ./global-metadata.patched.dat --list 456
```

## Automation guidance

For an LLM or agent workflow:

1. Confirm that the input path exists and is the intended metadata file.
2. Run `--info` and record the metadata version and string count.
3. Use `--search`, `--regex`, or `--dump --output` to identify exact indexes.
4. Require an explicit replacement map in `index=value` form before writing changes.
5. Write to a new output file; never overwrite the source.
6. Re-read the changed indexes and report the output path and any CLI errors.

The CLI is text-oriented rather than a native JSON-RPC tool. For larger pipelines, call it from a Python or shell wrapper and parse JSON produced by `--dump`. Do not send the complete metadata file to an LLM when a filtered search or selected JSON entries are sufficient.

## Limitations and safety

- Keep `global-metadata.dat` paired with the matching `libil2cpp.so` or `GameAssembly.dll`.
- A protected game may encrypt or obfuscate the on-disk metadata. A file that does not have a valid standard metadata header must be decoded or dumped in an authorized analysis workflow before using this CLI.
- Changing a string to a longer value may cause the tool to rebuild string offsets; validate the patched file with the target application or a disposable test copy.
- Changing metadata names does not change native method behavior. Logic changes require a native binary patch or an authorized runtime hook.
- Do not modify files in place, and do not expose proprietary game data unnecessarily in logs or model prompts.
- Use this workflow only for software and data that the user is authorized to analyze or modify.

Run the built-in help when an option or list syntax is uncertain:

```bash
"$METAEDIT" --help
```
