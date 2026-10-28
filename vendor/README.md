# vendor/ — 仓库内维护的第三方依赖

Photon 只有一个第三方依赖：Redis 客户端。它被 vendor 进本仓库，由我们维护。

## 为什么 vendor

上游 [xiusin/vredis](https://github.com/xiusin/vredis) 写于更早的 V 版本，在
V 0.5.2 上存在硬阻塞（`json` 模块迁移、`select` 分支变量可变性、`net` 超时语义）。
在此之前我们靠 `v install` + `scripts/patch-vredis.sh` 打补丁，代价是：

* CI / 本地 / Docker 三处各自打补丁，补丁脚本与上游版本强耦合
* 上游一次静默改动就能让补丁失配，而且失配时报的错离真因很远
* 没有任何针对 vredis 的测试，出问题只能靠上层缓存/队列偶发失败发现

vendor 进仓库之后：一份源码、一处修改、一套测试，`v.mod` 里不再声明外部依赖。

## 目录结构

```
vendor/
└── modules/
    └── xiusin/
        └── vredis/          # 来源：xiusin/vredis，之后由本仓库维护
            ├── vredis.v     # 连接、命令分发、JSON 帮工
            ├── protocol.v   # RESP 编解码
            ├── reply.v      # Reply 类型与错误传播
            ├── redis_pool.v # 连接池
            ├── string.v / hash.v / list.v / set.v / zset.v / stream.v
            ├── pubsub.v / script.v / hyper_log_log.v
            └── vredis_test.v # 本仓库新增的功能覆盖测试
```

## 为什么是 `vendor/modules/<owner>/<mod>`

V 的模块搜索规则只认 `<project>/` 与 `<project>/modules/`，且只认一层目录名。
`vendor/modules/xiusin/vredis` 同时满足两点：

* `modules/` 让 V 的 `source_root_from_vmod_root` 把 `vendor/` 当成模块根
* `xiusin/vredis` 让 `import xiusin.vredis` 的模块名原样命中，调用方零改动

代价：`v test vendor/modules/xiusin/vredis/` 在仓库根直接跑会找不到 `x.json2`
（单文件模式只拿文件所在目录当搜索根）。所以本地与 CI 统一走
`scripts/sync-vendor.sh` —— 把 `~/.vmodules/xiusin/vredis` 做成指向仓库内目录的
符号链接，之后 `v test cache/` 与 `v test vendor/modules/xiusin/vredis/` 都能从
`~/.vmodules` 找到 `x.json2`。

```sh
sh scripts/sync-vendor.sh   # 或 make vendor
```

这条命令是幂等的，可以放进本地脚本或 CI 的任意一步。

## 与上游的差异（都在源码里有注释）

| 位置 | 改动 | 原因 |
| --- | --- | --- |
| `import json` | → `import x.json2` | V 0.5.2 的 JSON 模块挂在 `x.json2` |
| `reply.go` … `Reply` 读取器 | 错误回复统一转成 Result error | 见下 |
| `SetOpts` 字段 | 加 `pub:` | 模块外根本无法构造 `SetOpts{nx: true}` |
| `Pool.get()` | `select` 分支改用 `ClientHandle` | V 0.5.2 的 select 分支变量不可变 |
| `Protocol.read_line()` | 新增 `read_exact_line()` | `TcpConn.read_line()` 在 `\r\n` 行尾会提前返回，导致订阅流错位 |
| `pubsub()` | 返回 `&Reply` 而非 `string` | 数组回复被 `bytestr()` 读成空串 |
| `subscribe_()` | 超时改 `24h` 而非 `0` | `net` 把 `read_timeout = 0` 当「立刻超时」，订阅一条消息都收不到 |

### 错误回复不再被静默丢掉

上游把 `-ERR ...` 解析成 `Reply.kind == .error` 之后就不再处理。所有返回值型命令
都用 `.ok()` / `.int()` / `.str()` 判读，于是：

* `SET k v NX` 撞上已存在的键（nil 回复）→ `false`，看着像「业务不满足」，其实要区分
* `INCR` 打在非数字值上（`-ERR`）→ `.int()` 把错误文本 `int()` 成 `0`
* `RENAME` 目标不存在（`-ERR`）→ `.ok()` 为 `false`

调用方拿到的都是「不报错但结果是错的答案」。现在所有 `!T` 命令包装都会先过
`reply_or_err()`，把错误回复转成 Result error 再由 `!` 往上传。

## 测试

```sh
make test-vendor          # 需要本机 127.0.0.1:6379 的 Redis
```

`vredis_test.v` 覆盖连接、字符串/哈希/列表/集合/有序集合、键空间、JSON 帮工、
Lua 脚本、发布订阅、连接池、RESP 编码边界。Redis 不可达时整体 skip 并打印原因，
不会把「本机没装 Redis」伪装成通过。

## 升级上游

```sh
# 1. 拉上游到临时目录，只取 .v 源码
git clone --depth 1 https://github.com/xiusin/vredis /tmp/vredis-upstream
cp /tmp/vredis-upstream/*.v vendor/modules/xiusin/vredis/
# 2. 重新应用上面表格里的差异（每个改动点在源码里都有注释标记）
# 3. 跑 make test-vendor + make test-all
```
