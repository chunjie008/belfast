# DNS 配置说明

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
