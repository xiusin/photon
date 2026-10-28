# xiusin.vredis（vendored）

本目录是 Photon 仓库内的 vendored 副本，源自 [xiusin/vredis](https://github.com/xiusin/vredis)
（MIT）。上游同步之后由本仓库维护，完整理由、目录布局与升级流程见
[`/vendor/README.md`](../../../README.md)。

## 与上游的差异

见 [`/vendor/README.md`](../../../README.md) 的「与上游的差异」一节。
每个改动点在源码里都有注释说明原因。

## 测试

```sh
make vendor                # sh scripts/sync-vendor.sh
make test-vendor           # 需要 127.0.0.1:6379 的 Redis
```

`vredis_test.v` 覆盖协议编解码、连接池生命周期、各数据类型命令、JSON 帮工、
Lua 脚本、发布订阅。Redis 不可达时整体 skip 并打印原因。
