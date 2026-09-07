# ⚓ Belfast

Belfast 是手机游戏《碧蓝航线》（[Azur Lane](https://en.wikipedia.org/wiki/Azur_Lane)）的私有服务器重实现，使用 [Go](https://go.dev/) 编写，并采用 [Iris](https://www.iris-go.com/) 和 [Gorm](https://gorm.io)。它面向 iOS 和 Android 客户端运行，无需越狱或 root 权限。

![Packet progress](https://cdn.molly.sh/belfast/implem.png)

# 🌟 功能

Belfast 目前具备以下功能：

- 底层多路复用 TCP 服务器，支持同时建立多个连接。
- 跟踪游戏更新，并自动导入舰船、道具等数据（美服版本）。
- 提供简洁的 API，可快速实现新的游戏消息，无需繁琐摸索。
- 完善的数据包分析工具，能够保存每个数据包，并提供 `protobuf` -> `json` 反序列化功能。
- 提供 Swagger 文档和管理端点的 REST API，便于服务器工具开发。
- 正在开发中的 Web UI：https://github.com/ggmolly/belfast-web。
- 基于配置的数据包响应填充功能，便于快速原型开发。
- 数据包进度管理工具和基于 Webhook 的状态更新功能。
- 运行时配置开关（维护模式、主机/端口覆盖）。

# ⚙️ 配置

- `cmd/belfast` 默认使用 `server.toml`（游戏服务器配置）。
- `cmd/gateway` 默认使用 `gateway.toml`（网关配置）。
- 区域通过 `[region].default`（`CN`、`EN`、`JP`、`KR`、`TW`）配置，默认为 `EN`。
- 网关服务器列表定义在 `[[servers]]` 中；可为每台服务器设置可选的 `name` 作为显示文本。网关会通过游戏协议（`CS_10022` -> `SC_10023`）探测每台游戏服务器，以获取服务器状态和负载。
- 如需将 Git 提交信息嵌入状态信息，请使用 `-ldflags "-X github.com/ggmolly/belfast/internal/buildinfo.Commit=$(git rev-parse --short HEAD)"` 进行构建。

# 🐛 问题反馈

- 请使用 GitHub Issue 表单提交错误报告和功能请求。
- 错误报告支持选择区域，并可附加以下调试文件：
  - `.pcap` 抓包文件
  - ADB 监视器（`-a` / `--adb`）生成的 logcat 输出
- 收集 ADB 日志时可使用以下本地命令：
  - `go run ./cmd/belfast -a`

# 🌠 项目状态

Belfast 正在重实现游戏中的全部功能（后台任务除外）。

# 🚀 路线图

1. 清理和完善代码
2. 实现数据包重实现 100% 覆盖
3. 实现游戏跟踪功能（管理员可在服务器配置中选择启用）
4. 持续维护 [belfast-web](https://github.com/ggmolly/belfast-web)
