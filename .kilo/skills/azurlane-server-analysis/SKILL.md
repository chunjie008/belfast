---
name: azurlane-server-analysis
description: Analyze and repair the Belfast Azur Lane backend using version-pinned Lua scripts, Android/ADB evidence, protobuf, packet captures, and Go handlers.
---

# Azur Lane Server Analysis

Use this skill when investigating or repairing the Belfast backend for the
Android Azur Lane client, especially when the observed client is an older CN
build (`com.bilibili.azurlane`). The extracted Lua repository is a reference
dataset. It is not the server implementation and it must not be treated as
proof of server behavior without packet or runtime evidence.

## Project-specific source layout

The existing repository tools expect the Lua checkout at the project root:

```text
./AzurLaneLuaScripts/
  CN/
  versions/CN.txt
./internal/tools/proto_from_lua.py
```

`AzurLaneLuaScripts` is intentionally ignored by the project `.gitignore`.
Keep it as a local, read-only checkout rather than committing extracted game
files. The sync helper is:

```bash
./.kilo/skills/azurlane-server-analysis/scripts/sync-lua-source.sh
```

The helper is CN-only and supports two sparse profiles:

- `cn`: the complete `CN` tree plus the small upstream `versions` metadata tree
  for behavior, protocol, and data analysis. It can be substantially larger
  than the protocol-only profile.
- `cn-protocol`: only `CN/net/protocol` plus version metadata, for lightweight
  schema lookup.

Examples:

```bash
# Use the reproducible default snapshot and the CN checkout.
./.kilo/skills/azurlane-server-analysis/scripts/sync-lua-source.sh \
  --profile cn

# Select a commit known to match a particular client build.
AZURLANE_LUA_REF=<commit-or-tag> \
  ./.kilo/skills/azurlane-server-analysis/scripts/sync-lua-source.sh \
  --profile cn

# Use only CN protocol descriptors for a lightweight lookup.
./.kilo/skills/azurlane-server-analysis/scripts/sync-lua-source.sh \
  --profile cn-protocol

# Inspect the exact revision after syncing.
git -C AzurLaneLuaScripts show -s --format='%H %cI %s' HEAD
```

Do not silently replace a pinned revision with `main`. The upstream repository
updates automatically, while this project is often used with an older client.
The Lua revision, client build, CN region, and any generated protocol revision
must be recorded in the analysis result.

## When to use

Use the Lua source to investigate:

- Request and response message names, fields, types, and numeric IDs.
- Region-specific protobuf schema differences.
- Client-side validation, defaults, state transitions, and formulas.
- Static configuration keys and relationships between data tables.
- A missing or incomplete Belfast packet handler.
- A mismatch between an old client and the current generated protobuf files.

Use the other project skills when the evidence is not in Lua:

- `jadx-cli` or `apk-repack` for APK and DEX inspection.
- `unitypy` for Unity asset and embedded text extraction.
- `il2cppinspector-redux-cli`, `ghidra-headless`, or `unidbg-ops` for native
  code and runtime analysis.
- The packet and ADB workflows already present in this repository for wire and
  runtime evidence.

## Establish the client and region first

Before interpreting a script, identify the installed package and build. Do not
assume that the latest upstream files match the phone:

```bash
adb get-state
adb shell dumpsys package com.bilibili.azurlane
adb shell pm path com.bilibili.azurlane
```

Record the version name, version code, APK path, ABI, and region. If the CN
package is absent, stop using CN assumptions and identify the actual package.
The package constant in `internal/debug/adb_watcher.go` has historically
targeted the EN package, so verify that the `-a` watcher actually observes the
installed CN client before relying on its output.

For reproducible analysis, keep a small metadata record outside tracked source
files containing:

```text
client package:
client version name:
client version code:
client APK hash (if available):
region:
AzurLaneLuaScripts commit:
evidence files:
```

Never put account credentials, session tokens, authorization headers, or
unfiltered personal logcat data into that record or into a prompt.

## Search before reading

The repository is large. Search narrowly and read only the relevant excerpts.
Do not send the complete checkout or a large generated file to the model.
Use the Kilo Grep tool when available; if shell search is needed, use `rg` when
installed or `git grep` as a fallback.

For a packet ID or message symbol:

```bash
rg -n --glob '*.lua' '17109|CS_17109|SC_17110' \
  AzurLaneLuaScripts/CN/net/protocol

# Fallback when rg is unavailable.
git -C AzurLaneLuaScripts grep -n -E '17109|CS_17109|SC_17110' -- \
  CN/net/protocol

rg -n 'CS_17109|SC_17110|RegisterPacketHandler\(17109' \
  internal
```

For behavior and formulas:

```bash
rg -n --glob '*.lua' 'function .*get|function .*request|function .*response' \
  AzurLaneLuaScripts/CN/model/vo AzurLaneLuaScripts/CN/model

rg -n --glob '*.lua' 'chapterleveldata|ship_data_statistics|result|default' \
  AzurLaneLuaScripts/CN
```

For static data keys, inspect the matching `sharecfg` or `sharecfgdata` file
only after locating the model or handler that consumes it. Prefer a filtered
entry over loading an entire table.

Always cite the exact region, relative path, and pinned commit for a Lua fact.
Line numbers are useful, but they are not stable across upstream updates.

## Protocol and protobuf workflow

The checked-in `internal/tools/proto_from_lua.py` was written for a comparison
of all five regions and currently expects `EN`, `CN`, `JP`, `KR`, and `TW`
protocol directories. A CN-only checkout is intentionally not sufficient for
that script. For ordinary CN investigation, search `CN/net/protocol` directly
and compare it with the existing generated Go types. Do not fetch other regions
just to satisfy the generator unless the task explicitly requires a cross-region
schema regeneration.

If a deliberate multi-region regeneration is needed, document that exception,
obtain the additional source separately, and inspect every generated change.
Run `make proto` only when regeneration is intended. It may update many Go
protobuf bindings, so keep unrelated generated changes out of a focused repair:

```bash
make proto
git status --short
git diff --stat
```

When comparing a message, check all of the following rather than relying on a
name match:

1. The numeric packet ID in the dispatcher and Lua call site.
2. The request and response field numbers and protobuf types.
3. Required, optional, and repeated labels.
4. Region-specific variants and namespace suffixes.
5. Actual wire data from a matching PCAP or decoded packet.
6. The current Go handler, ORM state, and response defaults.

The existing parser path is hard-coded to `./AzurLaneLuaScripts`. A custom
checkout directory is suitable for ad-hoc searching, but it will not work with
the parser unless its path and region assumptions are deliberately changed and
tested.

## ADB and packet evidence

Use the existing ADB watcher when appropriate:

```bash
go run ./cmd/belfast -a
```

Pair every captured log or PCAP with the client build and region. Preserve raw
captures and write decoded or redacted derivatives to a separate ignored
directory. When a response differs from the Lua expectation, compare the wire
bytes, protobuf decoding, handler return path, database state, and client-side
error handling in that order.

Do not infer that a client-side check is enforced by the server. Mark each
statement in an investigation as one of:

- `observed`: directly present in a matching Lua file, PCAP, log, or test.
- `inferred`: supported by multiple observations but not directly observed.
- `hypothesis`: plausible and requiring a new reproduction or capture.

## Backend repair workflow

For a missing or broken feature:

1. Reproduce the client action and preserve a minimal PCAP/logcat excerpt.
2. Identify the request and response IDs in the wire data and Lua protocol.
3. Locate the registry entry, handler, protobuf types, ORM models, and tests.
4. Compare the relevant CN Lua behavior with the selected client revision.
5. Implement the smallest compatible Go change; do not copy client-only state
   into server state without an authorization or persistence model.
6. Add a focused handler, serialization, persistence, or region regression test.
7. Run formatting and the narrowest relevant tests first, then the full suite.
8. Verify the response against a disposable test account or test database and,
   when authorized, the matching device build.

Useful checks include:

```bash
gofmt -w <changed-go-files>
go test ./internal/...
go test ./...
```

Do not overwrite the original APK, native library, metadata, PCAP, Lua source,
or database while testing. Generated output and patched artifacts belong in a
separate directory.

## Evidence report format

End an investigation or repair with a compact record like this:

```text
Client: com.bilibili.azurlane, <version name>/<version code>
Region: CN
Lua revision: <full commit>
Packet(s): CS_<id> -> SC_<id>
Observed: <direct evidence and paths>
Inferred: <cross-checked interpretation>
Changed: <Go/protobuf/SQL files>
Tests: <commands and results>
Residual risk: <version, region, or evidence gap>
```

If the selected Lua revision does not match the phone build, say so explicitly
and treat current-source results as a comparison, not a compatibility claim.

## Operating rules

- Use only software, device data, and captures the user is authorized to
  analyze or modify.
- Keep extracted source local and read-only; the upstream repository does not
  declare a license in its repository metadata, so do not assume unrestricted
  redistribution rights.
- Preserve originals and avoid destructive cleanup of source or evidence.
- Process large trees incrementally with bounded searches and excerpts.
- Do not expose secrets or unrelated user data in command output or reports.
- Do not claim that a server rule, formula, or packet field is confirmed from a
  client script alone.
- Prefer the CN tree for `com.bilibili.azurlane`, but verify region-specific
  differences before changing shared Go code.
