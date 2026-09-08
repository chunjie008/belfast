# DNS 配置说明

## 2026-09-08 排障结论

客户端无法连接私服的根因与修复：

1. **公网 53 端口不可达**：运营商/云平台拦截或未转发公网 UDP/TCP 53，外部查询
   `186.241.94.102:53` 到不了服务器上的 dnsmasq（tcpdump 确认无入站包）。
   纯 DNS 方案对公网客户端不可用。
2. **客户端 DNS 顺序**：手机 WiFi 第一个 DNS 是路由器的 IPv6 链路本地地址，
   即使 53 可达也可能不走我们的 DNS。
3. **客户端替代方案（已采用）**：手机已 root（APatch），用 bind mount 的 hosts 劫持：
   - 记录文件：`/data/adb/belfast-hosts`（SELinux 上下文必须是 `system_file`，
     否则 netd 读取 `/system/etc/hosts` 会 EACCES，静默回退到 DNS 查询）。
   - 开机脚本：`/data/adb/service.d/belfast-hosts.sh`，执行
     `mount --bind /data/adb/belfast-hosts /system/etc/hosts`。
4. **服务器侧修复**：
   - `gateway.toml` 增加 `require_private_clients = false`：经 nginx stream 代理后
     来源恒为 127.0.0.1，Go `net.IP.IsPrivate()` 不认 loopback，默认开启会拒绝所有连接。
   - `[[servers]]` 的 `ip`/`port` 必须填客户端可达地址（`186.241.94.102:20000`，
     由 nginx stream 转发到 belfast 7000），不能填 127.0.0.1。
   - gateway 进程 region 默认为 EN，取到的资源 hash 与 CN 客户端不符
     （表现为客户端"Hash文件校验失败"）。gateway.toml 现支持 `[region] default = "CN"`。
   - 服务器 `/etc/hosts` 保留 `203.107.54.123 line1-login-bili-blhx.bilibiligame.net`，
     供后端 `GameUpdate/GetHashes` 绕过本机 DNS 劫持直连官方 gateway 拉取资源 hash
     （否则解析到自己，缓存为空 hash）。

## 当前部署

本机使用 `dnsmasq` 提供 DNS 缓存和递归转发服务。

- 配置文件：`/etc/dnsmasq.d/belfast-local.conf`
- 服务名称：`dnsmasq.service`
- 本机网卡地址：`10.0.52.6`
- 公网出口地址：`186.241.94.102`
- DNS 监听：`127.0.0.1:53`、`10.0.52.6:53`
- 上游配置：`/run/systemd/resolve/resolv.conf`

公网地址没有直接配置在本机网卡上，当前环境通过 NAT 映射到 `10.0.52.6`。外部客户端使用 `186.241.94.102` 作为 DNS 地址，云平台需要将 TCP/UDP 53 转发到本机。

## 当前记录

`/etc/dnsmasq.d/belfast-local.conf` 中已配置：

```ini
# Belfast (Azur Lane CN) login endpoints.
host-record=line1-login-bili-blhx.bilibiligame.net,186.241.94.102
host-record=line1-bak-login-bili-blhx.bilibiligame.net,186.241.94.102
```

验证：

```bash
dig @127.0.0.1 line1-login-bili-blhx.bilibiligame.net A +short
dig @127.0.0.1 line1-bak-login-bili-blhx.bilibiligame.net A +short
dig @10.0.52.6 line1-login-bili-blhx.bilibiligame.net A +short
```

预期均返回：

```text
186.241.94.102
```

## 添加单个主机记录

编辑：

```text
/etc/dnsmasq.d/belfast-local.conf
```

追加一行，将示例域名替换为实际域名：

```ini
host-record=game.example.com,186.241.94.102
```

`host-record` 适合单个完整主机名。添加多个主机名时，每个记录单独一行：

```ini
host-record=game.example.com,186.241.94.102
host-record=api.example.com,186.241.94.102
```

如果需要将整个域名及其子域名统一指向同一个地址，可以使用：

```ini
address=/example.com/186.241.94.102
```

## 校验和生效

修改后执行：

```bash
sudo dnsmasq --test
sudo systemctl restart dnsmasq.service
systemctl is-active dnsmasq.service
```

注意：`reload`（SIGHUP）只清空缓存并重读 `/etc/hosts`，不会重读 `/etc/dnsmasq.d/` 下的配置文件，必须使用 `restart` 让新配置生效。

查询本地记录：

```bash
dig @127.0.0.1 game.example.com A +short
dig @10.0.52.6 game.example.com A +short
```

预期返回：

```text
186.241.94.102
```

其他没有本地记录的域名会按照 `resolv-file` 中的上游 DNS 继续递归转发，因此客户端仍可以解析其他网站。

## 公网访问注意事项

外部客户端应将 DNS 服务器设置为：

```text
186.241.94.102
```

安全组需要放行 TCP 和 UDP 的 53 端口。当前服务同时提供递归转发；如果安全组对整个互联网开放，任何人都可以使用它查询任意域名，形成开放递归 DNS。添加本地记录不会消除这个风险，生产环境应限制来源地址或改用只提供权威解析的独立服务。
