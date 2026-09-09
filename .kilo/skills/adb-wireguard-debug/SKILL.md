---
name: adb-wireguard-debug
description: Connect to an Android device over WireGuard and verify ADB, DNS, LAN routing, and split-tunnel behavior.
---

# ADB over WireGuard

Use this skill when the Android device is reachable through the project's
WireGuard tunnel and runtime evidence is needed through ADB. This is a
diagnostic workflow, not a replacement for USB pairing or Android debugging
authorization.

## Defaults

The current deployment uses these values:

```bash
export ADB_DEVICE="${ADB_DEVICE:-10.66.66.4:5555}"
export WG_GATEWAY="${WG_GATEWAY:-10.66.66.1}"
export LAN_TARGET="${LAN_TARGET:-10.0.52.6}"
```

The defaults are environment-specific. Override them when inspecting another
peer or LAN, and never place WireGuard private keys in this skill or in logs.

## Connect and authorize

The WireGuard profile must already be enabled on the phone. Connect ADB with a
bounded timeout so a missing route does not block the terminal:

```bash
timeout 5s adb connect "$ADB_DEVICE"
adb devices -l
```

The device must show `device`, not `offline` or `unauthorized`. For
`unauthorized`, unlock the phone and accept the Android RSA debugging prompt.
If no prompt appears, reconnect ADB over USB, enable USB debugging, accept the
computer key, and retry the network connection.

Run a shell command against the intended device explicitly:

```bash
adb -s "$ADB_DEVICE" shell 'id; getprop ro.product.model'
```

Use `adb -s` for every command when more than one device may be connected.

## Identify the client

Before interpreting game behavior, record the installed package and build:

```bash
adb -s "$ADB_DEVICE" shell dumpsys package com.bilibili.azurlane
adb -s "$ADB_DEVICE" shell pm path com.bilibili.azurlane
```

Verify the actual package, version name, version code, ABI, and region. Do not
assume that a CN analysis applies if the installed package is different.

## Verify WireGuard and split routing

Inspect interfaces and policy routes:

```bash
adb -s "$ADB_DEVICE" shell 'ip -brief addr; ip route show table all'
adb -s "$ADB_DEVICE" shell "ip route get $WG_GATEWAY"
adb -s "$ADB_DEVICE" shell "ip route get $LAN_TARGET"
adb -s "$ADB_DEVICE" shell 'ip route get 1.1.1.1'
```

Expected split-tunnel behavior:

- The WireGuard interface, usually `tun0`, has the assigned `10.66.66.x`
  address.
- The WireGuard gateway uses the tunnel interface.
- The selected LAN target uses the tunnel interface.
- An external address such as `1.1.1.1` uses the normal Wi-Fi or mobile-data
  interface, not the tunnel.

Test reachability separately:

```bash
adb -s "$ADB_DEVICE" shell "ping -c 2 -W 2 $WG_GATEWAY"
adb -s "$ADB_DEVICE" shell "ping -c 2 -W 2 $LAN_TARGET"
```

Do not treat a single lost ICMP packet as proof that WireGuard is broken;
check the route and the server-side handshake as well.

## Verify DNS

The WireGuard Android profile should specify the server's tunnel address as
DNS, normally `10.66.66.1`. Verify both the locally overridden game hostname
and an ordinary external hostname:

```bash
adb -s "$ADB_DEVICE" shell \
  'ping -c 1 -W 3 line1-login-bili-blhx.bilibiligame.net'
adb -s "$ADB_DEVICE" shell \
  'ping -c 1 -W 3 example.com'
```

The game hostname should resolve to the configured Belfast public address
unless the deployment intentionally uses a tunnel-only address. The external
hostname should also resolve through dnsmasq's upstream resolver.

`getprop net.dns1` may be empty or unhelpful on newer Android releases. Prefer
the hostname resolution test and server-side dnsmasq logs when confirming DNS.

## Verify the server peer

On the WireGuard server, confirm that the expected peer has a recent handshake
and the assigned tunnel address:

```bash
sudo wg show wg0
```

The server peer's `AllowedIPs` normally contains only the phone's tunnel
address, for example `10.66.66.4/32`. Additional entries may be intentional;
do not remove them without checking the deployment requirement.

## Belfast-specific evidence

For game-client runtime logs, use the existing watcher when appropriate:

```bash
go run ./cmd/belfast -a
```

Pair logcat or packet evidence with the client package, version, and region.
Redact account identifiers, session tokens, authorization headers, and other
personal data before storing or sharing output.

## Troubleshooting order

1. Confirm WireGuard is enabled on the phone and the server peer has a recent
   handshake.
2. Confirm `adb connect` reaches the device and Android reports `device`.
3. Confirm `tun0` and the expected tunnel address exist on the phone.
4. Confirm route selection for the WireGuard gateway, LAN target, and external
   target.
5. Confirm DNS resolution for both a Belfast hostname and an external hostname.
6. Only then inspect Belfast logs, packet handlers, or game-level failures.
