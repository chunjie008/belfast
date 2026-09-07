---
name: il2cppinspector-redux-cli
description: Analyze Unity IL2CPP binaries and metadata with the installed Il2CppInspector Redux CLI.
---

# Il2CppInspector Redux CLI

Use the Linux x64 installation at `~/.local/tools/il2cppinspector/Il2CppInspectorRedux.CLI-linux-x64`.
The executable is:

```bash
~/.local/tools/il2cppinspector/Il2CppInspectorRedux.CLI-linux-x64/Il2CppInspector.Redux.CLI
```

The command alias `il2cppinspector` is available through `~/.local/bin` after loading `~/.bashrc`.
The CLI requires the .NET 10 runtime and ASP.NET Core 10 runtime.

## When to use

Use this skill when the user wants to:

- Analyze a Unity IL2CPP binary and its `global-metadata.dat` file.
- Generate C# stubs, dummy DLLs, C++ scaffolding, or disassembler metadata.
- Extract IL2CPP files from a Unity installation or game package.
- Generate a Visual Studio solution from IL2CPP data.
- Inspect command-line options or automate IL2CPP analysis.

## Check availability

```bash
il2cppinspector --help
il2cppinspector process --help
dotnet --list-runtimes
```

Use the explicit path if the shell has not loaded the user PATH:

```bash
~/.local/tools/il2cppinspector/Il2CppInspectorRedux.CLI-linux-x64/Il2CppInspector.Redux.CLI --help
```

## Core command shape

```bash
il2cppinspector process <InputPath> [OPTIONS]
```

`<InputPath>` may be a file or directory. The tool keeps loading the supplied input paths until it finds the required IL2CPP binary and metadata files. For a typical Unity game, pass the binary and metadata paths together:

```bash
il2cppinspector process \
  ./GameAssembly.so \
  ./global-metadata.dat \
  -o ./il2cpp-output
```

On Android, the binary is commonly named `libil2cpp.so`; on Windows it is commonly `GameAssembly.dll`.

## Output examples

Generate C# stub source:

```bash
il2cppinspector process \
  ./libil2cpp.so ./global-metadata.dat \
  -o ./il2cpp-output \
  -s
```

Generate dummy DLLs:

```bash
il2cppinspector process \
  ./libil2cpp.so ./global-metadata.dat \
  -o ./il2cpp-output \
  -d
```

Generate C++ scaffolding:

```bash
il2cppinspector process \
  ./libil2cpp.so ./global-metadata.dat \
  -o ./il2cpp-output \
  --output-cpp-scaffolding
```

Generate disassembler metadata:

```bash
il2cppinspector process \
  ./libil2cpp.so ./global-metadata.dat \
  -o ./il2cpp-output \
  -m
```

Generate a Visual Studio solution:

```bash
il2cppinspector process \
  ./GameAssembly.dll ./global-metadata.dat \
  -o ./il2cpp-output \
  --output-vs-solution
```

Extract IL2CPP files:

```bash
il2cppinspector process \
  ./game-files \
  -o ./il2cpp-output \
  --extract-il2cpp-files
```

## Useful options

- `-o, --output <path>` sets the output directory.
- `-s, --output-csharp-stub` generates C# stub code.
- `-d, --output-dummy-dlls` generates dummy DLLs.
- `-m, --output-disassembler-metadata` generates disassembler metadata.
- `--output-cpp-scaffolding` generates C++ scaffolding.
- `--output-vs-solution` generates a Visual Studio solution.
- `--unity-version <version>` supplies the Unity version when it cannot be detected.
- `--compiler-type <type>` supplies the compiler type when it cannot be detected.
- `--unity-path <path>` points to a Unity installation.
- `--unity-assemblies-path <path>` points to Unity managed assemblies.
- `--extract-il2cpp-files` extracts IL2CPP-related files.
- `--image-base <address>` sets the image base for formats that require it.
- `--name-translation-map <path>` supplies a name translation map.
- `--layout`, `--flatten-hierarchy`, and `--sorting-mode` control generated stub layout and ordering.
- `--suppress-metadata` suppresses metadata output where supported.
- `--compilable` requests compilable generated output where supported.
- `--separate-assembly-attributes` separates generated assembly attributes.
- `--disassembler <name>` selects the disassembler metadata format.

Always check the installed release for exact option values and accepted enum names:

```bash
il2cppinspector process --help
```

## Operating rules

- Treat game binaries and metadata as user data; never overwrite the original files.
- Use a new output directory for each unrelated analysis.
- Keep `libil2cpp.so` or `GameAssembly.dll` paired with the matching `global-metadata.dat` from the same build.
- Do not assume that a successful file load means symbols or metadata were fully recovered.
- Preserve tool warnings and report missing, incompatible, or unsupported inputs.
- Use `-o` explicitly in repeatable or automated workflows.
- Do not pass secrets or unrelated user data to scripts or command arguments.
- Run `il2cppinspector process --help` instead of guessing uncommon option values.

## Common workflow

1. Confirm the input paths exist and identify the IL2CPP binary and metadata file.
2. Verify that both inputs come from the same Unity build.
3. Choose a non-conflicting output directory.
4. Run `il2cppinspector process <InputPath> -o <output-directory>` with the required output flags.
5. Check the exit status and generated files.
6. Report warnings, missing files, unsupported formats, and partial output.
