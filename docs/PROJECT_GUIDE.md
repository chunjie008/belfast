# Belfast 项目说明

本文档基于当前仓库源码整理，面向需要运行、维护、扩展或分析 Belfast 的开发者。文档描述的是代码现状，不等同于完整的产品部署手册；游戏客户端、协议字段和外部数据源变化后，部分内容需要随版本更新。

## 1. 项目定位

Belfast 是《碧蓝航线》客户端的私有服务器重实现，使用 Go 编写。它不是传统 HTTP 游戏后端，而是同时提供以下几类能力：

- 游戏客户端使用的 TCP 服务，接收带有自定义头部的 protobuf 消息并返回 protobuf 响应。
- 网关服务，负责返回可用游戏服务器列表，或在代理模式下转发 TCP 流量。
- 面向管理工具和 Web UI 的 REST API，使用 Iris 提供路由、JSON 响应和 Swagger 页面。
- 基于 PostgreSQL 的持久化层，使用 `sqlc` 生成查询代码，并通过嵌入式 SQL migration 初始化数据库。
- 游戏静态数据和版本/哈希数据导入能力。
- 抓包解码、ADB 日志监视、数据包覆盖率统计和 Webhook 自动生成进度图等辅助工具。

项目支持 CN、EN、JP、KR、TW 五个区域。区域会影响部分协议处理、重置时间和响应选择。

## 2. 目录结构

```text
cmd/
  belfast/          游戏服务器入口
  gateway/          网关入口
  packet_progress/  数据包实现进度分析器
  pcap_decode/      PCAP/PCAPNG TCP 重组及 protobuf 解码器
  webhook_server/   GitHub Webhook 触发进度图更新
internal/
  answer/            游戏请求处理器及各业务域实现
  api/               REST API、路由、中间件、请求处理器和类型
  auth/              管理端会话、密码、Passkey/WebAuthn、CSRF、限流
  authz/             权限操作和 capability 定义
  config/            TOML 配置结构、默认值和维护模式持久化
  connection/        TCP Server、Client、收发包、队列和连接生命周期
  db/                PostgreSQL 连接、Store、迁移、sqlc 生成代码
  debug/              调试抓包/ADB 相关逻辑
  entrypoint/        两个服务的启动编排及协议注册
  orm/                游戏领域模型和数据库访问封装
  packets/            包头解析、注册表、区域化 handler、分发器
  protobuf/           生成的 protobuf Go 类型，包含 CS_/SC_ 消息
  region/             当前区域管理
  scheduler/          定时任务和区域重置时钟
  tools/              协议/数据辅助脚本
docs/
  swagger.yaml/json  REST API OpenAPI 描述
internal/db/migrations/
                    按版本排序的嵌入式 PostgreSQL migration
```

仓库中还可能出现 `bin/`、`run/`、`logs/`、`apk/`、`server.toml` 等本地运行或分析产物。它们不是核心源码；其中配置、日志、APK 和抓包文件可能包含环境信息或敏感数据，不应直接提交。

## 3. 服务组成

### 3.1 游戏服务器 `cmd/belfast`

入口仅调用 `entrypoint.Run`，默认读取 `server.toml`。启动流程如下：

1. 初始化日志、区域和协议 handler 注册表。
2. 解析 `--config`、`--no-api`、`--reseed`、`--adb` 等命令行参数。
3. 加载 TOML，并设置端口、私有客户端限制等默认值。
4. 初始化数据库、执行 PostgreSQL migration，并确保默认权限/角色存在。
5. 检查 `items` 表是否已有游戏数据；没有数据时调用 `misc.UpdateAllData` 导入当前区域数据。
6. 如果指定 `--reseed`，强制重新导入游戏数据。
7. 创建 TCP Server；除非指定 `--no-api`，同时在 API 端口启动 REST API。
8. 接收 SIGINT，向在线客户端发送断开消息后退出。

TCP 端口缺省为 80；当前 Nginx 部署将 Belfast 后端放在 `127.0.0.1:7000`，由公网 TCP `20000` 入口转发。示例配置和当前本地配置使用 API 端口 2289（API 端口应在 `[api].port` 中显式配置）。源码中的 TCP server 为每个连接启动独立 goroutine；每个 Client 又有独立的包分发循环。

### 3.2 网关 `cmd/gateway`

网关默认读取 `gateway.toml`，有两种模式：

- `serve`：本地处理网关协议，通常返回 `[[servers]]` 配置中的服务器列表，并通过协议探测后端状态。
- `proxy`：将客户端 TCP 连接透明转发到 `proxy_remote`。代理连接建立超时由 `proxy_dial_timeout_ms` 控制，默认 5000ms。

网关会监视配置文件所在目录。`require_private_clients` 等部分配置可以热更新；监听地址、端口和模式变化会记录日志并提示需要重启，不会自动重建监听器。

### 3.3 Nginx TCP 入口

当前部署使用 Nginx `stream` 模块作为公网 TCP 入口，不使用普通的 `http` 反向代理：

```text
客户端 -> Nginx:80       -> Gateway:127.0.0.1:8080
客户端 -> Nginx:20000    -> Belfast:127.0.0.1:7000
管理端 -> Belfast:2289
```

项目内的部署模板位于 `deploy/nginx/`：

- `belfast-stream.conf`：定义 80 和 20000 两个 TCP upstream/server。
- `nginx.conf`：包含 `stream` 顶层配置和 `streams-enabled` 目录。

Ubuntu/Debian 部署步骤：

```bash
sudo apt-get install -y nginx
sudo mkdir -p /etc/nginx/streams-enabled
sudo install -m 0644 deploy/nginx/nginx.conf /etc/nginx/nginx.conf
sudo install -m 0644 deploy/nginx/belfast-stream.conf /etc/nginx/streams-enabled/belfast.conf
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

后端配置应使用 loopback 地址：

```toml
# server.toml
[belfast]
bind_address = "127.0.0.1"
port = 7000
proxy_port = 20000
```

```toml
# gateway.toml
bind_address = "127.0.0.1"
port = 8080
proxy_port = 20000
```

Nginx 的 `proxy_protocol` 不应开启，因为 Belfast 当前协议解析器不接收额外的 PROXY protocol 头。长连接使用 `proxy_timeout = 1h`；如果客户端连接时出现超时，应同时检查 Nginx upstream、Belfast/Gateway 进程和云平台 NAT。

### 3.4 REST API

API 在 `internal/api/app.go` 中组装，顺序为恢复异常、请求日志、CORS、鉴权和审计中间件，然后注册业务路由。Swagger UI 地址为：

```text
http://<host>:<api-port>/swagger/
```

主要路由域包括：

- `/health`：健康检查。
- `/api/v1/auth`：管理员 bootstrap、登录、登出、session、密码和 Passkey。
- `/api/v1/admin/users`：管理员用户管理。
- `/api/v1/admin/authz`、`/api/v1/admin/permission-policy`：角色、权限和账户覆盖策略。
- `/api/v1/me`：当前用户/管理员对应的指挥官、资源、权限和发放操作。
- `/api/v1/players`：玩家查询、删除、资源、舰船、装备、建造、舰队、章节、商店、活动等管理操作。
- `/api/v1/game-data` 及静态数据路由：读取游戏模板数据。
- `/api/v1/shop`、`/api/v1/notices`、`/api/v1/exchange-codes`：商店、公告和兑换码。
- `/api/v1/dorm3d-apartments`、`/api/v1/juustagram`、`/api/v1/activities`：特色业务和运营数据。

具体方法、参数和响应模型以 `docs/swagger.yaml` 为准；不要仅根据本概览拼接 API 请求。

## 4. TCP 协议和请求处理

### 4.1 包格式

每个包的前 7 字节是 Belfast 使用的固定头部：

| 偏移 | 长度 | 含义 |
| --- | --- | --- |
| 0 | 2 | 包长度，大端序；长度字段表示后续包内容，不包含自身 2 字节 |
| 2 | 1 | 保留字段，当前写入 `0x00` |
| 3 | 2 | packet ID，大端序，例如 `11001` |
| 5 | 2 | packet index，大端序，用于关联请求和响应 |
| 7 | 可变 | protobuf payload |

`connection.GeneratePacketHeader` 生成响应头，payload 长度加 5 后写入长度字段。`packets.HEADER_SIZE` 为 7。接收端先读取两字节长度，再读取剩余内容；小于 5 的长度会被视为非法。

### 4.2 收包、排队和分发

`connection.Server.HandleConnection` 完成连接准入、维护模式判断、私网地址判断和客户端登记。收到数据后进入有界队列：

1. 网络读取协程将数据写入 ring buffer。
2. 主连接循环按包头读取完整包，并放入 Client 队列。
3. 分发循环从队列取包，调用 `packets.Dispatch`。
4. Dispatch 根据 packet ID 查找 `PacketDecisionFn`，依次执行一个或多个 `PacketHandler`。
5. handler 将响应写入 Client 的 buffer；当前包处理完成后统一 `Flush` 到 TCP 连接。

队列上限为 512，包缓冲池容量为 128。队列阻塞、handler 错误、写错误和处理包数量会在连接关闭时记录。

### 4.3 Handler 注册

游戏协议注册集中在 `internal/entrypoint/packet_registry.go`，网关协议注册在 `gateway_packets.go`。handler 签名为：

```go
type PacketHandler func(*[]byte, *connection.Client) (int, int, error)
```

第一个返回值通常是写入字节数，第二个返回值是响应 packet ID，第三个返回错误。新增请求通常需要：

1. 在 protobuf 定义/生成结果中存在对应 `CS_` 和 `SC_` 类型。
2. 在 `internal/answer` 增加 handler，并完成输入校验、状态变更和响应构造。
3. 在 `registerPackets` 注册请求 ID。
4. 对有区域差异的请求使用 `RegisterLocalizedPacketHandler`。
5. 增加 handler 单元测试或协议级测试。

未注册请求会记录 missing packet，并返回 `SC_10998`，其 `Cmd` 为原请求 ID，`Result` 为不支持命令。handler 返回错误会记录错误并关闭客户端连接。

### 4.4 区域化处理

区域由 `[region].default` 设置，只允许 `CN`、`EN`、`JP`、`KR`、`TW`。`RegisterLocalizedPacketHandler` 在注册时根据当前区域选择对应 handler，没有专属 handler 时回退到 `Default`。区域不仅影响协议，也会影响 `scheduler.ResetClock` 的日/周/月重置边界。

## 5. 数据库和领域层

### 5.1 数据库现状

运行时入口 `db.InitDefaultStore` 当前走 PostgreSQL：先使用 `database/sql` 建立连接并执行 migration，再使用 `pgxpool` 建立查询池。`db.Store` 同时持有连接池和 `sqlc` 生成的 `gen.Queries`，提供 `WithTx` 和 `WithPGXTx` 事务辅助方法。

migration 文件通过 `go:embed` 编译进二进制，文件名格式为 `NNNN_name.sql`。启动时会：

- 按版本排序读取 migration。
- 对每个 migration 计算 SHA-256 checksum。
- 使用 PostgreSQL advisory lock 防止多个实例并发迁移。
- 将已执行版本和 checksum 写入 `schema_migrations`。
- 如果已执行 migration 的 checksum 变化，直接报错，防止静默修改历史结构。

`sqlc.yaml` 从 `internal/db/migrations` 和 `internal/db/queries` 生成 `internal/db/gen`，SQL 方言和生成包使用 pgx/v5。

### 5.2 领域模型

`internal/orm` 是游戏状态访问层，围绕 commander、owned ship、equipment、item、fleet、mail、guild、shop、activity、chapter、island、dorm3d、educate 等实体组织代码。`internal/answer` 负责协议语义，ORM 负责读取/修改持久化状态，二者之间通过领域模型和 helper 连接。

多数业务操作遵循以下模式：

1. 从 Client 的 `Commander` 或数据库加载玩家状态。
2. 校验资源、模板 ID、所有权、次数和时间窗口。
3. 在事务中写入状态。
4. 构造一个或多个 `SC_` 响应和推送消息。
5. 由 Dispatch 末尾统一发送。

### 5.3 初始玩家

首次认证或创建玩家时，代码会创建账户映射、指挥官根记录、初始舰船、初始库存和默认舰队。无教程流程时会额外设置默认秘书舰；具体行为由 `connection.Client.CreateCommander` 和 `CreateCommanderWithStarter` 实现，修改初始内容前应同时检查相关测试和客户端登录流程。

## 6. 游戏数据更新

`internal/misc/game_update.go` 从 `belfast-data` 的 `versions.json` 获取区域版本信息。游戏哈希优先从 `.cached_hashes` 读取；缓存区域或版本不匹配时，通过区域网关发送 `CS_10800`，解析 `SC_10801` 后缓存结果。

服务器启动时，如果 `items` 表为空，会调用 `UpdateAllData` 导入静态数据。数据导入依赖当前区域、外部数据仓库和本地 importer；网络不可用或数据版本不兼容时，启动可能失败或保持数据不完整。`--reseed` 会主动触发重新导入，应在维护窗口执行。

## 7. 配置说明

### 7.1 游戏服务器配置

`server.example.toml` 是配置模板，`server.toml` 通常是本机实际配置。常用字段：

| 配置 | 作用 |
| --- | --- |
| `[belfast].bind_address` / `port` | 游戏 TCP 后端监听地址和端口；直连部署端口缺省为 80，Nginx 部署通常使用 `127.0.0.1:7000` |
| `[belfast].proxy_port` | 更新检查/服务器互联响应中公布的代理端口，缺省为 20000 |
| `[belfast].maintenance` | 维护模式；开启后拒绝新连接并断开现有连接 |
| `[belfast].require_private_clients` | 限制客户端来源为私有 IP；未填写时默认为 true |
| `[api].enabled` / `port` | REST API 开关和端口 |
| `[api].cors_origins` | CORS 允许来源 |
| `[auth]` | 管理员 session、cookie、CSRF、Argon2、WebAuthn 和限流参数 |
| `[database]` | DSN、schema 名称和 migration 选项 |
| `[region].default` | 当前游戏区域 |
| `[create_player]` | 新玩家跳过 onboarding、昵称黑名单和非法字符正则 |
| `[[servers]]` | 网关/服务器列表信息，也可被部分服务状态 API 使用 |

### 7.2 网关配置

`gateway.example.toml` 支持 `bind_address`、`port`、`proxy_port`、`mode`、`proxy_remote`、`proxy_dial_timeout_ms` 和 `require_private_clients`。`proxy_port` 缺省为 20000，并会进入网关加载后的运行时配置。`[[servers]]` 至少应配置 `id`、`ip`、`port`；`name` 用于显示，`assert_online` 可跳过协议探测并强制标记在线。

### 7.3 重要安全默认值

- 私有客户端限制默认开启；对公网开放前必须评估并显式配置网络边界。
- 使用 Nginx 部署时，安全组通常只开放 TCP `80` 和 `20000`；`7000`、`8080`、`2289` 应限制为本机或管理网段。
- `proxy_port = 20000` 只是协议中公布的客户端端口，必须确保确实有 Nginx 或其他 TCP 代理监听并转发到游戏后端。
- 生产环境不应使用 `cors_origins = ["*"]`。
- `disable_auth` 只能用于受控开发环境。
- `cookie_secure`、WebAuthn RP ID/origin、管理密码和 `WEBHOOK_SECRET` 必须按实际 HTTPS/域名部署调整。
- DSN、管理凭据、抓包、ADB 日志和 Webhook 密钥不得提交到 Git。

注意：配置结构仍保留 `sqlite`、`mysql` 等字段和模板注释，但当前 `entrypoint.Run` 调用的默认 Store 初始化实现是 PostgreSQL 路径。若要使用非 PostgreSQL 驱动，应先确认对应 runtime 实现，而不能仅依据模板字段判断已支持。

## 8. 辅助命令

### 8.1 构建和代码生成

```bash
go test ./...
make build
make build-belfast
make build-gateway
make swag
make sqlc
make proto
```

`make proto` 需要 `protoc`、`protoc-gen-go` 和可用的协议源；协议源目录被 `.gitignore` 忽略，不能把原始 `.proto` 文件提交到仓库。`make sqlc-check` 会生成查询并检查 `internal/db/gen` 是否产生差异。

### 8.2 启停脚本

```bash
./start.sh
./stop.sh
./restart.sh
CONFIG=server.toml ./start.sh
SKIP_BUILD=1 ./start.sh
```

脚本默认构建 `./cmd/belfast` 到 `bin/belfast`，PID 写入 `run/belfast.pid`，日志写入 `logs/belfast.log`。`start.sh` 会等待配置中的 API 端口，若无 API 端口则等待游戏端口。脚本使用 `nohup`，适合简单本地/单机运行，不替代 systemd、容器编排或正式进程监管。

### 8.3 PCAP 解码

```bash
go run ./cmd/pcap_decode \
  -pcap capture.pcapng \
  -server-port 7000 \
  > decoded.ndjson
```

工具使用 gopacket 重组 TCP 流，按 7 字节头部提取包，并依据服务端端口推断 `CS`/`SC` 方向。已知 protobuf 会输出 JSON；未知 ID 或反序列化失败时输出 `raw_hex` 和错误。可用 `-limit`、`-packet`、`-packet-name CS_12002`、`-stream` 缩小结果。抓包内容可能包含账户信息，处理后应妥善保管。

### 8.4 数据包进度

```bash
go run ./cmd/packet_progress \
  -out-json docs/packet-progress.json \
  -out-svg docs/packet-progress.svg
```

默认同时统计 `CS_` 和 `SC_`。分析器扫描 packet 注册、`internal/answer` handler、protobuf 类型、数据库写入和响应发送等 AST 信号，给 handler 计算启发式分数，分类为 `implemented`、`partial`、`stub`、`panic` 或 `missing`。`cmd/packet_progress/overrides.json` 可修正已知误判，`heuristics.json` 可调整权重和阈值。该结果是覆盖率指标，不是行为正确性的证明。

### 8.5 ADB 与 Webhook

`go run ./cmd/belfast -a` 开启实验性的 ADB logcat 监视；`-f` 启动时清空 logcat，`-r` 尝试重启游戏且必须配合 `-a`。该功能源码注释标明主要面向 Linux。

`cmd/webhook_server` 暴露 `/health` 和带 HMAC-SHA256 校验的 `POST /webhook`。收到合法请求后依次执行 `git pull --ff-only` 和 `go run ./cmd/packet_progress png`。运行前需设置 `WEBHOOK_SECRET`；仓库路径、PNG 路径和监听地址可通过 `WEBHOOK_*` 环境变量调整。当前默认路径是部署作者的本地路径，生产部署必须显式覆盖。

## 9. 测试与开发流程

提交改动前建议按以下顺序执行：

1. 阅读目标业务域现有的 `*_test.go`，确认测试 helper、数据库 fixture 和区域行为。
2. 先写协议/领域测试，再实现 handler 或 ORM 变更。
3. 对 Go 文件执行 `gofmt`。
4. 执行 `go test ./...`；涉及 SQL 时确认 PostgreSQL 测试环境可用。
5. 若修改查询或 migration，执行 `make sqlc-check`，并检查 migration 版本与 checksum 规则。
6. 若修改路由或 API 类型，执行 `make swag` 并检查 `docs/swagger.*` 是否需要更新。
7. 检查 `git diff`，确认没有 DSN、密钥、APK、PCAP、日志或生成的临时文件。

贡献规范要求 PR 保持小而单一、避免未经讨论的重构、谨慎升级依赖，并且不提交受版权保护的材料或原始 `.proto` 文件。

## 10. 常见排障路径

### 服务无法启动

- 先查看 `logs/belfast.log` 或直接前台运行二进制。
- 检查配置路径是否存在，TOML 是否能解析。
- 检查 PostgreSQL DSN、用户权限、schema 和端口。
- 确认监听端口未被其他进程占用。
- Nginx 部署时依次检查 `sudo nginx -t`、`systemctl status nginx`、`127.0.0.1:7000` 和 `127.0.0.1:8080`。
- 如果错误出现在数据导入，检查外部数据源、区域和当前版本。

### 客户端被拒绝

- 确认没有开启 `maintenance`。
- 检查客户端 IP 是否为私网地址；开发环境可显式关闭 `require_private_clients`。
- 确认客户端连的是网关端口还是游戏端口。
- 如果使用 Nginx，确认云安全组已放行 TCP `80` 和 `20000`，且 Nginx 的两个 upstream 分别指向 `8080` 和 `7000`。
- 查看是否发生重复登录、handler 错误或 `SC_10998`。

### 收到不支持命令

- 从日志或调试输出获得 `CS_` ID。
- 在 `internal/protobuf` 查找对应请求/响应类型。
- 在 `internal/answer` 搜索已有相近业务处理器。
- 在 `packet_registry.go` 注册 handler，并添加测试。
- 使用 `pcap_decode` 对照真实客户端请求和预期响应。

### 数据库状态异常

- 不要修改已执行 migration；新增 migration 修复结构。
- 检查 `schema_migrations` 中的版本和 checksum。
- 需要重新灌入静态数据时使用维护窗口和 `--reseed`。
- 检查玩家状态修改是否在事务中完成，尤其是资源扣除和奖励发放。

### API 无法访问

- 确认没有使用 `--no-api`，且 `[api].enabled = true`。
- 检查 API 端口而不是游戏 TCP 端口。
- 首次部署先检查 `/health`，再访问 `/swagger/`。
- 登录、CSRF、cookie 和 Passkey 问题优先核对 `[auth]` 的 origin、RP ID、secure cookie 和时间 TTL。

## 11. 当前边界和维护重点

- 项目目标是持续覆盖客户端协议，但 README 中的“全部功能”不应理解为每个功能都已完成或经过生产验证。
- `packet_progress` 的 SC 统计目前按发现到的响应使用情况计入实现，不能替代端到端测试。
- 外部版本数据和客户端协议会变化，生成的 protobuf、数据导入器、handler 和 migration 需要协同更新。
- 当前运行编排以 PostgreSQL 为实际主路径；非 PostgreSQL 配置字段的可用性需要以后续代码为准。
- 网关配置热更新能力是部分的，监听地址/端口/模式变化仍需重启。
- Webhook 服务存在部署路径和外部命令依赖，适合受控内网使用；必须自行补充反向代理、超时、访问日志和进程监管。

## 12. 关键入口速查

| 目标 | 入口 |
| --- | --- |
| 游戏服务启动 | `cmd/belfast/main.go` -> `internal/entrypoint.Run` |
| 网关启动 | `cmd/gateway/main.go` -> `internal/entrypoint.RunGateway` |
| Nginx TCP 部署 | `deploy/nginx/nginx.conf`、`deploy/nginx/belfast-stream.conf` |
| TCP 收包 | `internal/connection/server.go` |
| Client 队列 | `internal/connection/client.go` |
| 包解析与分发 | `internal/packets/handler.go` |
| 游戏协议注册 | `internal/entrypoint/packet_registry.go` |
| 网关协议注册 | `internal/entrypoint/gateway_packets.go` |
| REST API 组装 | `internal/api/app.go` |
| API 路由 | `internal/api/routes/` |
| 管理鉴权 | `internal/auth/`、`internal/api/middleware/` |
| 权限模型 | `internal/authz/` |
| 数据库初始化 | `internal/db/bootstrap.go` |
| migration 执行 | `internal/db/migrator.go` |
| 查询生成 | `sqlc.yaml`、`internal/db/queries/` |
| 游戏数据更新 | `internal/misc/game_update.go`、`update_data_*.go` |
| 抓包解码 | `cmd/pcap_decode/main.go` |
| 覆盖率分析 | `cmd/packet_progress/main.go` |
