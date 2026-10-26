#!/bin/sh
# patch-vredis.sh — 让 xiusin.vredis 能在 V 0.5.2 下编译
#
# v.mod 依赖的 xiusin.vredis 写于更早的 V 版本，在 0.5.2 下有两处硬阻塞：
#
#  1. 仍 `import json`。V 0.5.2 已删除 json 模块，改用 json2。
#  2. `select { client := <-p.connections }` 分支变量不再隐式可变，
#     后续 `test_on_borrow(mut client)` / `client.is_active = true` 编不过。
#     把可变性搬到结构体字段上（ClientHandle.conn）是唯一不需要
#     unsafe 的写法。
#
# 用完可删：等上游 vredis 更新后，这里退化成 no-op 也不会报错。

set -e

VMOD="${VMODULES:-$HOME/.vmodules}/xiusin/vredis"

if [ ! -d "$VMOD" ]; then
    echo "patch-vredis: $VMOD not found, run \`v install xiusin.vredis\` first" >&2
    exit 1
fi

python3 - "$VMOD" <<'PY'
import sys, pathlib

root = pathlib.Path(sys.argv[1])
redis_v = root / 'redis.v'
pool_v = root / 'redis_pool.v'

s = redis_v.read_text()
if 'import json\n' in s:
    s = s.replace('import json\n', 'import json2\n', 1)
    s = s.replace('r.set(key, json.encode(val))', 'r.set(key, json2.encode(val))')
    s = s.replace('json.decode(T, raw)', 'json2.decode[T](raw)')
    s = s.replace('return json.encode(val)', 'return json2.encode(val)')
    redis_v.write_text(s)
    print('patch-vredis: redis.v -> json2')

s = pool_v.read_text()
if 'struct ClientHandle' not in s:
    s = s.replace(
        'pub fn (mut p Pool) get() !&ActiveRedisConn {',
        '// ClientHandle 把可变性搬到字段上：select 分支变量在 V 0.5.2 里是不可变的。\n'
        'struct ClientHandle {\n'
        'mut:\n'
        '\tconn &ActiveRedisConn = unsafe { nil }\n'
        '}\n\n'
        'pub fn (mut p Pool) get() !&ActiveRedisConn {',
        1,
    )
    s = s.replace(
        '''			mut client := <-p.connections {
				// Account for the connection leaving the idle queue.
				p.mu.@lock()
				p.idle--
				p.mu.unlock()

				// Validate the idle connection before handing it out.
				if !p.is_conn_valid(client) {
					client.close() or {}
					continue
				}
				if !isnil(p.opt.test_on_borrow) {
					p.opt.test_on_borrow(mut client) or {
						client.close() or {}
						continue
					}
				}
				client.is_active = true
				return client
			}''',
        '''			client := <-p.connections {
				// Account for the connection leaving the idle queue.
				p.mu.@lock()
				p.idle--
				p.mu.unlock()

				mut handle := ClientHandle{
					conn: client
				}

				// Validate the idle connection before handing it out.
				if !p.is_conn_valid(handle.conn) {
					handle.conn.close() or {}
					continue
				}
				if !isnil(p.opt.test_on_borrow) {
					p.opt.test_on_borrow(mut handle.conn) or {
						handle.conn.close() or {}
						continue
					}
				}
				handle.conn.is_active = true
				return handle.conn
			}''',
        1,
    )
    pool_v.write_text(s)
    print('patch-vredis: redis_pool.v -> ClientHandle')
PY

echo "patch-vredis: done ($VMOD)"
