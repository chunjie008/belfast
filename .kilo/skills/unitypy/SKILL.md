---
name: unitypy
description: Extract, inspect, modify, and export Unity asset files with the installed UnityPy Python package.
---

# UnityPy

Use UnityPy from the dedicated Linux virtual environment:

```bash
source ~/.local/venvs/unitypy/bin/activate
```

Or invoke its Python directly:

```bash
~/.local/venvs/unitypy/bin/python
```

Installed version: UnityPy 1.25.3.

## When to use

Use this skill when the user wants to:

- Load Unity assets, serialized files, AssetBundles, APK-extracted data, or WebFiles.
- Enumerate and inspect Unity object types.
- Extract textures, sprites, text assets, audio clips, meshes, fonts, and other resources.
- Export decoded assets to files such as PNG, WAV, and text.
- Modify supported Unity objects and save the result to a new file.
- Process Unity game resource directories in a repeatable Python script.

## Supported resource workflows

UnityPy is commonly used with:

- Serialized Unity asset files such as `.assets` and `.sharedAssets`.
- AssetBundles and bundle files.
- WebFiles and Unity resource containers.
- Unity files extracted from APK, OBB, or game data directories.
- Common Unity object classes including `Texture2D`, `Sprite`, `TextAsset`, `AudioClip`, `Mesh`, `Font`, `MovieTexture`, `MonoBehaviour`, and `GameObject`.

Actual support depends on the Unity version, file format, compression, encryption, and object serialization layout. Report unsupported or partially decoded objects instead of assuming that every object can be exported.

## Basic loading and inspection

```python
from pathlib import Path
import UnityPy

source = Path("./resources/sharedassets0.assets")
env = UnityPy.load(str(source))

print("container entries:", len(env.container))
for obj in env.objects:
    print(obj.path_id, obj.type.name, obj.byte_size)
```

`UnityPy.load()` accepts a file path, a path-like object, or file data. When processing a directory, load individual files rather than passing unrelated files as one logical asset.

Inspect parsed data for an object:

```python
for obj in env.objects:
    if obj.type.name == "TextAsset":
        data = obj.read()
        print(data.m_Name, len(data.m_Script))
```

Use the object's type name and `read()` result to access the version-specific parsed fields. Do not rely on fields from a different Unity version without checking the decoded object.

## Export common assets

Export textures and sprites:

```python
from pathlib import Path
import UnityPy

source = Path("./resources")
out = Path("./extracted")
out.mkdir(parents=True, exist_ok=True)

env = UnityPy.load(str(source))
for obj in env.objects:
    if obj.type.name == "Texture2D":
        data = obj.read()
        image = data.image
        if image is not None:
            image.save(out / f"{data.m_Name}_{obj.path_id}.png")
    elif obj.type.name == "Sprite":
        data = obj.read()
        image = data.image
        if image is not None:
            image.save(out / f"{data.m_Name}_{obj.path_id}.png")
```

Export text assets:

```python
from pathlib import Path
import UnityPy

out = Path("./extracted-text")
out.mkdir(parents=True, exist_ok=True)
env = UnityPy.load("./resources/sharedassets0.assets")

for obj in env.objects:
    if obj.type.name != "TextAsset":
        continue
    data = obj.read()
    payload = data.m_Script
    if isinstance(payload, bytes):
        payload = payload.decode("utf-8", errors="replace")
    (out / f"{data.m_Name}_{obj.path_id}.txt").write_text(payload, encoding="utf-8")
```

Export audio clips when UnityPy provides decoded audio data:

```python
from pathlib import Path
import UnityPy

out = Path("./audio")
out.mkdir(parents=True, exist_ok=True)
env = UnityPy.load("./resources/sharedassets0.assets")

for obj in env.objects:
    if obj.type.name != "AudioClip":
        continue
    data = obj.read()
    for name, audio in data.samples.items():
        audio.export(out / f"{data.m_Name}_{name}")
```

## Modify and save

Read a supported object, change a field, and save to a new destination:

```python
from pathlib import Path
import UnityPy

source = Path("./resources/sharedassets0.assets")
destination = Path("./modified/sharedassets0.assets")
destination.parent.mkdir(parents=True, exist_ok=True)

env = UnityPy.load(str(source))
for obj in env.objects:
    if obj.type.name != "TextAsset":
        continue
    data = obj.read()
    data.m_Script = data.m_Script.replace(b"old", b"new")
    data.save()

destination.write_bytes(env.file.save())
```

Modification support is object- and Unity-version-dependent. Keep the original file unchanged and test modified output with a disposable copy of the target game or project.

## AssetBundle and encryption hooks

Load an AssetBundle through the same environment API:

```python
import UnityPy

env = UnityPy.load("./data.unity3d")
for obj in env.objects:
    print(obj.type.name)
```

For a bundle that uses a known supported decryption key, configure it before loading:

```python
import UnityPy

UnityPy.set_assetbundle_decrypt_key("known-key")
env = UnityPy.load("./encrypted-bundle")
```

Only use keys supplied or authorized by the user. Do not guess keys or attempt to bypass access controls.

## Operating rules

- Preserve original Unity files; write extraction and modified output to a separate directory.
- Use unique names containing the object path ID when exporting because Unity object names are not guaranteed to be unique.
- Treat APK, OBB, AssetBundle, and metadata contents as user data.
- Check `obj.type.name` before calling type-specific fields or exporters.
- Handle `None`, missing fields, unsupported compression, and decode exceptions per object so one bad asset does not hide all results.
- Keep logs concise and never print credentials, decryption keys, or unrelated user data.
- Do not claim that an asset was recovered if UnityPy emitted a decode or export error.
- For large resource trees, process files incrementally and avoid loading the entire game directory into memory at once.
- Use the installed environment's Python rather than the system Python:

```bash
~/.local/venvs/unitypy/bin/python script.py
```

## Common workflow

1. Confirm the input file or resource directory exists.
2. Choose separate extraction and modified-output directories.
3. Load one Unity resource file or bundle with `UnityPy.load()`.
4. Filter objects by `obj.type.name` and call `read()` only for relevant types.
5. Export or modify supported objects, recording per-object failures.
6. Verify output files and report unsupported, encrypted, or partially decoded assets.
