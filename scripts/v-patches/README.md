# scripts/v-patches — 需要在本地 V 编译器上打的补丁

这里放的是**编译器侧**的补丁。它们不属于框架代码，所以不放进 `vlib/`，
但复现本框架在 V 0.5.2 上的行为又离不开它们。每份补丁都写清了
「为什么必须在编译器里改」，而不是在框架里绕。

用法（假设 V 源码在 `$VROOT`，版本 0.5.2 / `7647ce1`）：

```sh
cd "$VROOT"
git apply /path/to/photon/scripts/v-patches/0001-checker-skip-veb-app-check-for-route-attrs.patch
make local=1            # 重新自举（注意：boostrap 阶段需要 -gc none，见下文）
```

## 0001 — 带路由属性的方法跳过 veb app 参数检查

**问题**：Photon 的核心约定是控制器方法收 `(mut ctx veb.Context, params map[string]string)`，
`params` 由 `web/mount.v` 的 comptime 派发生成。而 V 0.5.2 的
`checker.fn_decl()` 把**任何**返回 `veb.Result` 的方法都当成 veb app 方法，
只放行 `string / 整数 / bool`，于是本框架的核心用法整体不可编译
（`example/verify` 里 7 个方法全中招，`web/mount_test.v` 同理）。

**为什么只能在编译器里改**：把控制器签名改成 `string` 就得放弃路径参数，
那不是「绕开检查」，是把框架能力砍掉。

**补丁做两件事**：

1. 只在 `veb.Result` 真的存在于类型表（`typ_veb_result > 0`）时才进这段检查。
   `find_type()` 找不到时返回**负值**，而方法返回类型在某些阶段也可能是负值——
   两个负值直接比较会相等，于是**没 import veb 的模块里任意方法都被误判**。
2. 方法上带 `@[get]/@[post]/@[put]/@[delete]/@[patch]/@[head]/@[options]/@[route]`
   时跳过检查。这些属性意味着路由由框架自己派发，跟 veb 的「参数从 URL 段填充」无关；
   veb 自己的路由方法不带这些属性，所以检查对 veb 本身依然生效。

**验证**：

```v
// 带属性 → 放行
@[get: '/users/:id']
pub fn (mut c Ctrl) show(mut ctx veb.Context, params map[string]string) veb.Result
// 不带属性 → 仍然报错（veb 原本的约束不放松）
pub fn (mut c Ctrl) show(mut ctx veb.Context, params map[string]string) veb.Result
```

## 附：自举用的 `vc` 快照必须与 tag 同批

这条不是补丁，是一条踩坑记录，写在这里省得重复踩：

`vc/v.c` 跟上游 `master` 滚动。拿「当前 master 的 `vc`」去引导 0.5.2，
会得到 82 条类型系统内部形状漂移的错误：

```
error: sum type reference requires `ast.Node` storage
error: cannot use `0` as `&ast.ScopeObject` outside `unsafe`
error: cannot use `int` as `ast.Type` in argument 1 to ...
```

正确做法是按 tag 提交时间挑 `vlang/vc` 的同批快照。0.5.2（`7647ce1`，2026-07-13）
对应 `vlang/vc` 的 `7eb8c54a`（`[v:master] 45ae01d - V 0.5.2`）。

```sh
git clone --filter=blob:none https://github.com/vlang/vc /tmp/vc
git -C /tmp/vc checkout 7eb8c54a
cp /tmp/vc/v.c /tmp/vc/v_win.c "$VROOT/vc/"
```

另外两件环境上的事：`thirdparty/tcc` 的预编译 `tcc` 与 `libgc.a` 在较新的
glibc 上不可用（`undefined reference to sigsetjmp`），删掉 `thirdparty/tcc`
让它回退到系统 `cc` 即可；boehm GC 同理由 `-gc none` 绕开。
