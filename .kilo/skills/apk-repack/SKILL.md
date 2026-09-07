---
name: apk-repack
description: Repackage Android APKs by decoding, modifying, rebuilding, aligning, and signing with apktool, zipalign, and apksigner.
---

# APK Repack

Repackage an Android APK: decode it with apktool, modify smali code or resources, rebuild, zipalign, and sign with apksigner.

## Toolchain

All tools are installed on this machine:

- `apktool` 3.0.3 via `~/.local/bin/apktool` (jar at `~/.local/share/apktool/apktool.jar`, runs on the system Java).
- `~/Android/Sdk/build-tools/36.0.0/zipalign`
- `~/Android/Sdk/build-tools/36.0.0/apksigner`
- `keytool` from the GraalVM JDK for keystore generation.
- `jadx` for inspecting decompiled Java when smali alone is not enough.

The build-tools directory is not on PATH; use the full paths above or pick another version under `~/Android/Sdk/build-tools/` if the user requests one.

Check availability:

```bash
apktool --version
~/Android/Sdk/build-tools/36.0.0/apksigner --version
```

## When to use

Use this skill when the user wants to:

- Decode an APK into smali code and resources for modification.
- Patch smali, AndroidManifest.xml, resources, or assets, then rebuild a working APK.
- Repack and sign an APK so it can be installed on a device or emulator.
- Align and verify a rebuilt APK.

## Standard workflow

Work in a fresh working directory per APK and keep the original file untouched.

### 1. Decode

```bash
apktool d -f -o work app.apk
```

`-f` forces overwrite of the output directory. The result contains `smali*/`, `res/`, `AndroidManifest.xml`, `assets/`, and `apktool.yml`.

### 2. Modify

Edit files under `work/`:

- Smali code: `work/smali/`, `work/smali_classes2/`, etc.
- Manifest: `work/AndroidManifest.xml`
- Resources: `work/res/`
- Assets and unknown files: `work/assets/`, `work/original/`, `work/unknown/`

Use `jadx -d jadx-out app.apk` in parallel when readable Java helps locate the smali to patch. Do not delete `apktool.yml`; the build step needs it.

### 3. Rebuild

```bash
apktool b -o repacked-unsigned.apk work
```

If the build fails with resource errors, retry with `--use-aapt2` or inspect the named resource; report the apktool error verbatim instead of guessing.

### 4. Zipalign

```bash
~/Android/Sdk/build-tools/36.0.0/zipalign -p -f -v 4 repacked-unsigned.apk repacked-aligned.apk
```

Always align before signing; apksigner v2+ signatures require the alignment to happen first.

### 5. Sign

Reuse an existing keystore when the user provides one. Otherwise create a throwaway debug keystore once per workspace:

```bash
keytool -genkeypair -v -keystore debug.keystore -alias debug \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=Debug,O=Debug,C=CN"
```

Then sign and verify:

```bash
~/Android/Sdk/build-tools/36.0.0/apksigner sign \
  --ks debug.keystore --ks-pass pass:android --key-pass pass:android \
  --out repacked.apk repacked-aligned.apk
~/Android/Sdk/build-tools/36.0.0/apksigner verify --verbose repacked.apk
```

### 6. Report

Report the final signed APK path, the keystore used, and the apksigner verify result.

## Operating rules

- Never overwrite the user's original APK; write outputs to new files.
- Rebuilt APKs must be signed before installation; unsigned builds only serve as intermediate artifacts.
- A resigned APK has a different signature than the original: apps with signature checks may break, and it cannot install as an update over the original unless the original is uninstalled first. Warn the user about this.
- Keep the decode directory until the signed APK verifies successfully; it is the only place holding the modifications.
- Run `apktool --help` when an option is uncertain instead of guessing.
- If decoding fails on a protected or packed APK, report the failure and suggest analysis with `jadx` or other skills instead of forcing a rebuild.
