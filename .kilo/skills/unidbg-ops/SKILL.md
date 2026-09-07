---
name: unidbg-ops
description: Use unidbg to emulate Android ARM native libraries, inspect ELF modules, initialize JNI, and build repeatable Java smoke tests.
---

# Unidbg Operations

## Use this skill when

- Loading or testing an Android `armeabi-v7a` or `arm64-v8a` `.so` outside a device.
- Creating a unidbg emulator and selecting Unicorn2, Dynarmic, KVM, or another backend.
- Inspecting ELF modules, exported symbols, `JNI_OnLoad`, JNI registration, or native function calls.
- Building a small Java harness for an APK's native library.
- Diagnosing missing Android libraries, JNI stubs, unsupported syscalls, or a native call that hangs.

## Scope and safety

- Treat APKs and native libraries as untrusted input. Prefer read-only extraction and run test code in a dedicated analysis directory.
- Do not execute arbitrary native exports merely because they are present. First identify the Java/JNI signature and required arguments.
- Do not print secrets, keys, cookies, device identifiers, or application data while tracing JNI calls.
- Keep extracted libraries outside the APK and never overwrite the original APK.
- A successful `JNI_OnLoad` proves initialization only; it does not prove that business functions are callable.
- Stop a hanging harness before changing its code or launching another copy. Use a bounded external timeout for exploratory calls.

## Environment requirements

unidbg is a Java library, not a standalone GUI application. The source tree contains a Maven Wrapper and should be used instead of assuming a global `mvn` command.

The 0.9.x source uses Java 8 source and target settings. Keep Java 21 installed if needed by the rest of the machine, but run unidbg builds and harnesses with Java 8:

```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
java -version
```

Build and install the source tree without release signing:

```bash
cd /path/to/unidbg
./mvnw -DskipTests -Dgpg.skip=true install
```

`-Dgpg.skip=true` is for local use only; it avoids requiring the publisher's private GPG key. The resulting artifacts are installed into the current user's Maven repository.

## Dependency setup

For an Android harness, use the Android module. Add `unidbg-unicorn2` when explicitly selecting `Unicorn2Factory`:

```xml
<dependency>
    <groupId>com.github.zhkl0228</groupId>
    <artifactId>unidbg-android</artifactId>
    <version>0.9.9</version>
</dependency>
<dependency>
    <groupId>com.github.zhkl0228</groupId>
    <artifactId>unidbg-unicorn2</artifactId>
    <version>0.9.9</version>
</dependency>
```

When the project is built with the unidbg Wrapper, invoke a separate harness from the unidbg root so the Wrapper can find its own `.mvn/wrapper` files:

```bash
cd /path/to/unidbg
./mvnw -f /path/to/harness/pom.xml compile exec:java \
  -Dlibrary=/path/to/extracted/lib.so
```

Use an exec-maven-plugin version compatible with the Maven version downloaded by the Wrapper. If a recent plugin requires a newer Maven runtime, use an older compatible plugin or run the compiled class with an explicit dependency classpath.

## APK and ELF inspection

First identify available ABIs and libraries without extracting the whole APK:

```bash
APK=/path/to/app.apk
unzip -Z1 "$APK" | sed -n 's#^lib/\([^/]*\)/.*\.so$#\1#p' | sort -u
unzip -Z1 "$APK" | grep -E '^lib/[^/]+/.*\.so$' | sort
unzip -Z1 "$APK" | grep -E '(^|/)classes([0-9]*)?\.dex$' | sort
```

Extract only the candidate library into a disposable directory:

```bash
WORK=/tmp/unidbg-apk-test
mkdir -p "$WORK/lib/arm64-v8a"
unzip -p "$APK" lib/arm64-v8a/libtarget.so \
  > "$WORK/lib/arm64-v8a/libtarget.so"
readelf -h "$WORK/lib/arm64-v8a/libtarget.so"
readelf -d "$WORK/lib/arm64-v8a/libtarget.so" | grep NEEDED
```

Check whether a library has exported JNI entry points before trying to invoke them:

```bash
readelf -Ws "$WORK/lib/arm64-v8a/libtarget.so" \
  | awk '$7 != "UND" && $8 ~ /^Java_/ {print $8}'
readelf -Ws "$WORK/lib/arm64-v8a/libtarget.so" \
  | awk '$7 != "UND" && $8 == "JNI_OnLoad" {print $8}'
```

`JNI_OnLoad` may register methods dynamically, so the absence of `Java_...` exports does not mean the library has no JNI API.

## Minimal ARM64 smoke test

The first test should prove only the emulator boundary: create an ARM64 emulator, install an Android resolver, load the ELF, inspect the module, allocate guest memory, and call a safe libc function.

```java
import com.github.unidbg.AndroidEmulator;
import com.github.unidbg.Module;
import com.github.unidbg.Symbol;
import com.github.unidbg.arm.backend.Unicorn2Factory;
import com.github.unidbg.linux.android.AndroidEmulatorBuilder;
import com.github.unidbg.linux.android.AndroidResolver;
import com.github.unidbg.memory.Memory;
import com.github.unidbg.memory.MemoryBlock;

import java.io.File;

try (AndroidEmulator emulator = AndroidEmulatorBuilder.for64Bit()
        .setProcessName("unidbg-smoke")
        .addBackendFactory(new Unicorn2Factory(true))
        .build()) {
    Memory memory = emulator.getMemory();
    memory.setLibraryResolver(new AndroidResolver(23));
    Module module = emulator.loadLibrary(new File("/path/to/libtarget.so"), false);

    System.out.printf("module=%s base=0x%x size=0x%x%n",
            module.name, module.base, module.size);
    System.out.println("exportedSymbols=" + module.getExportedSymbols().size());

    Symbol jniOnLoad = module.findSymbolByName("JNI_OnLoad", false);
    System.out.println("JNI_OnLoad=" + (jniOnLoad == null ? "<missing>" :
            String.format("0x%x", jniOnLoad.getAddress())));

    MemoryBlock block = memory.malloc(64, false);
    try {
        block.getPointer().setString(0, "unidbg-smoke");
        Module libc = memory.findModule("libc.so");
        Number length = libc.findSymbolByName("strlen", false)
                .call(emulator, block.getPointer());
        System.out.println("strlen=" + length.longValue());
    } finally {
        block.free();
    }
}
```

For `armeabi-v7a`, replace `for64Bit()` with `for32Bit()` and select the 32-bit library. Do not load an ARM64 library into a 32-bit emulator or vice versa.

## JNI initialization

After the basic loader test succeeds, create the Dalvik VM and let unidbg load the library through the VM before calling `JNI_OnLoad`:

```java
VM vm = emulator.createDalvikVM();
vm.setVerbose(false);
DalvikModule dalvikModule = vm.loadLibrary(library, false);
dalvikModule.callJNI_OnLoad(emulator);
Module module = dalvikModule.getModule();
```

Interpret results in this order:

- Library load failure: inspect ELF class, ABI, `DT_NEEDED`, Android resolver version, and missing bundled dependencies.
- `JNI_OnLoad` failure: identify the first missing JNI method, class, field, or Android system call.
- `JNI_OnLoad` success but Java call failure: verify the class name, static/instance status, exact JNI descriptor, and dynamically registered method table.
- Native call hangs: treat it as a runtime diagnosis problem, not a success. Use a timeout, enable focused tracing, and check thread creation, blocking syscalls, entropy, time, networking, and unresolved callbacks.

## Calling a known JNI method

Only call a method after confirming its exact descriptor from DEX analysis, decompilation, Java source, or a known JNI registration table:

```java
DvmClass nativeClass = vm.resolveClass("com/example/NativeUtils");
DvmObject<?> result = nativeClass.callStaticJniMethodObject(
        emulator,
        "methodName(Ljava/lang/String;)Ljava/lang/String;",
        new StringObject(vm, "input"));
System.out.println(result.getValue());
```

Use the matching wrapper for the return type, such as `callStaticJniMethodInt` or `ByteArray`. Do not guess a descriptor for a production call; a wrong descriptor can obscure the real native dependency problem.

## Backend selection

Prefer an explicitly available backend when the default backend reports a missing native library:

```java
.addBackendFactory(new Unicorn2Factory(true))
```

Other backends may be appropriate when the host and project artifacts support them:

- Unicorn2: portable instruction emulation and a good default for repeatable smoke tests.
- Dynarmic: often faster for supported ARM workloads.
- KVM or Hypervisor: hardware-assisted options with host and privilege requirements.

A failure such as `Couldn't load library ... unicorn_java` usually means the harness selected the legacy backend or its native library is not on the runtime classpath. Add the matching backend dependency and select it explicitly; do not copy random native files into system directories.

## JNI and Android API stubs

Real applications commonly require callbacks that unidbg cannot infer automatically. Add only the missing behavior reported by the failing call:

- Resolve the exact class name used by the target.
- Implement the required `DvmClass`, `DvmObject`, field, or method behavior.
- Return the correct Java wrapper and type.
- Keep verbose JNI logging off during normal runs and enable it only around a failing boundary.

Avoid broad fake implementations or generic fallback return values. They can let execution continue while corrupting the native algorithm's state.

## Tracing and debugging

Use tracing after static inspection identifies a target function or a concrete failure point:

```java
emulator.traceCode();
// call one known function
```

For a function address, distinguish module-relative offset from the mapped address. A symbol's `getAddress()` is the callable address in the emulator; the ELF symbol value alone is not necessarily a host pointer.

Keep traces narrow. Do not dump all memory or all JNI arguments when they may contain credentials, keys, or personal data.

## Verification checklist

A useful report should state exactly which boundary passed:

- Java version and selected backend.
- APK ABI and extracted library path.
- ELF dependencies and whether they resolved.
- Module name, base, size, and export count.
- Whether `JNI_OnLoad` returned successfully.
- Exact JNI descriptor tested, if any.
- Return value or the first concrete failure.
- Whether the harness was bounded and whether temporary extraction files were removed.

Do not call a library “fully emulated” because it loaded or because `JNI_OnLoad` succeeded. Report unsupported dependencies and hangs separately from verified behavior.
