---
name: azurlane-cn-data
description: Query CN-region raw game data (sharecfgdata/ShareCfg JSON) from AzurLaneTools/AzurLaneData for Belfast handler implementation and test seeding. CN-only, memory-safe single-record lookup.
---

# Azur Lane CN Data Query

Use this skill when a Belfast handler or test needs real CN game configuration
data: field structures of a `sharecfgdata` table, a concrete record by ID, or a
version check against the upstream CN client data.

Scope is CN only. Do not fetch or reason about EN/JP/KR/TW data; this project
targets the CN client.

## Source

Upstream: `https://github.com/AzurLaneTools/AzurLaneData` (auto-updated).

Raw file layout (CN):

```text
https://raw.githubusercontent.com/AzurLaneTools/AzurLaneData/main/CN/<path>
```

Relevant trees:

- `CN/sharecfgdata/*.json` — split per-record tables consumed by Belfast
  handlers (e.g. `ship_data_template.json`, `item_data_statistics.json`,
  `chapter_template.json`, `task_data_template.json`, `island_*.json`).
- `CN/ShareCfg/*.json` — monolithic tables; larger, use only when the
  sharecfgdata split lacks the table.
- `CN/GameCfg/*.json` — client game configuration.
- `versions/CN.txt` — current CN client version string (e.g. `9.6.667`).

## Version pinning

Upstream updates automatically with each game patch. Before relying on any
record, check and record the version:

```bash
curl -s https://raw.githubusercontent.com/AzurLaneTools/AzurLaneData/main/versions/CN.txt
```

For reproducible analysis, pin a commit and use it in the raw URL:

```bash
curl -s "https://api.github.com/repos/AzurLaneTools/AzurLaneData/commits?path=CN&per_page=1" \
  | jq -r '.[0].sha'

# Then fetch from the pinned ref instead of main:
# https://raw.githubusercontent.com/AzurLaneTools/AzurLaneData/<sha>/CN/<path>
```

Record the version string and commit in the analysis result alongside the
client build under test.

## Memory-safe lookup workflow

Some tables exceed several MB (`ship_data_template.json` is ~2.7 MB). Never
load a whole table into context or into the model prompt. Fetch to `tmp/` and
extract only the needed record:

```bash
mkdir -p tmp/azurlane-data
curl -s -o tmp/azurlane-data/ship_data_template.json \
  https://raw.githubusercontent.com/AzurLaneTools/AzurLaneData/main/CN/sharecfgdata/ship_data_template.json

# Single record by id (tables are keyed objects: { "<id>": { ... }, ... }).
jq '."107021"' tmp/azurlane-data/ship_data_template.json

# Discover the top-level shape first if unknown.
jq 'keys | length' tmp/azurlane-data/ship_data_template.json
jq 'to_entries[0]' tmp/azurlane-data/ship_data_template.json
```

If a table is an array instead of a keyed object, filter with
`jq '.[] | select(.id == 107021)'`. Check the shape with `jq 'type'` first.

Cache downloaded files in `tmp/azurlane-data/` (gitignored) for the duration of
a task and record the ref they came from; delete them when done. Do not commit
game data into the repository.

## Mapping to Belfast config entries

Belfast stores game data in the `config_entries` table:

- `category` = the sharecfgdata path, lowercase, e.g.
  `sharecfgdata/ship_data_template.json`
- `key` = the record ID as a string (see `configEntryKey` in
  `internal/misc/update_data_helpers.go`)
- `data` = the record JSON

To seed a test with real data, extract the record with jq and pass it to the
existing `seedConfigEntry` helper used across `internal/answer` tests:

```go
seedConfigEntry(t, "sharecfgdata/ship_data_template.json", "107021", payload)
```

## Relationship to the runtime data source

The Belfast server imports data from its own mirror `ggmolly/belfast-data`
(`internal/misc/update_data_helpers.go:15`), which mirrors the AzurLaneData
layout. AzurLaneData is the upstream reference for analysis and test seeding
only; do not repoint runtime fetch URLs at it. If the mirror lags upstream,
note the version gap explicitly rather than assuming field parity.

## Operating rules

- CN tree only; never fetch other regions.
- Pin and record the ref; upstream `main` moves with every game update.
- Stream and filter with jq; never paste whole tables into prompts.
- Keep downloads under `tmp/azurlane-data/`; treat them as disposable.
- The upstream repository declares no license; use data locally for analysis,
  do not redistribute.
- Real data confirms field structure and values, not server behavior; packet
  and handler evidence still follow the `azurlane-server-analysis` skill.
