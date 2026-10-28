# Checklist — Photon 深度优化 v2

## Phase 1: IoC/DI 容器深度改造
- [ ] BeanFactory / ListableBeanFactory / HierarchicalBeanFactory 接口定义
- [ ] Container 实现三个接口
- [ ] @[bean] 方法注解 comptime 扫描
- [ ] @[bean] 方法参数自动注入
- [ ] BeanDefinitionRegistryPostProcessor 接口 + refresh 集成
- [ ] @[profile] 注解 → OnProfileCondition
- [ ] 表达式引擎 (Photon EL): 属性访问、算术、比较、逻辑
- [ ] @[value] 集成表达式引擎
- [ ] @[conditional_on_expression] 条件
- [ ] 所有新增测试通过: `v test core/`

## Phase 2: AOP 增强
- [ ] Aspect / BeforeAdvice / AfterAdvice / AroundAdvice 接口
- [ ] 切点表达式解析器 (execution / annotation / within)
- [ ] @[aspect] 注解扫描
- [ ] comptime 织入通知
- [ ] 切点组合 (&& / || / !)
- [ ] 所有新增测试通过: `v test core/`

## Phase 3: ORM 优化
- [ ] Specification[T] 接口 + QueryPredicate
- [ ] Specifications 组合器 (where/and/or)
- [ ] PageRequest / Page[T] / Sort 类型
- [ ] find_all_paged() + count 自动生成
- [ ] @[modifying] 注解解析
- [ ] DTO 投影 find_projected[P]()
- [ ] RoutingPolicy + ReadWriteRoutingPolicy
- [ ] 所有新增测试通过: `v test orm/`

## Phase 4: Web MVC 改造
- [ ] @[request_body] JSON 反序列化
- [ ] @[path_param] / @[query_param] 类型转换
- [ ] ResponseEntity 链式构建器
- [ ] HandlerInterceptor 三阶段接口
- [ ] InterceptorRegistry
- [ ] @[rest_controller] 复合注解 + 自动 JSON 序列化
- [ ] WebMvcConfigurer 配置接口
- [ ] 所有新增测试通过: `v test web/`

## Phase 5: 缓存深度封装
- [ ] @[cache_config] 类级配置
- [ ] sync=true 同步加载注解
- [ ] CacheStats 统计 + /actuator/cache 端点
- [ ] CachingConfigurer 全局配置
- [ ] 所有新增测试通过: `v test cache/`

## Phase 6: 事件机制增强
- [ ] TypedEvent[T] 类型化事件
- [ ] @[event_listener] condition 表达式
- [ ] 事件继承传播
- [ ] 所有新增测试通过: `v test core/`

## Phase 7: 配置管理增强
- [ ] Placeholder 解析器 (${key:default})
- [ ] @ConfigurationProperties 验证
- [ ] PropertySource 优先级
- [ ] PHOTON_ 环境变量约定覆盖
- [ ] 所有新增测试通过: `v test config/`

## Phase 8: 日志系统增强
- [x] 多路输出：`Logger.add_sink(Channel)` + `FileChannel` / `StderrChannel` / `SyslogChannel`
      （未新增 `Appender` 接口：`Channel` 已经是同一层抽象，再加一层只增加心智成本）
- [ ] AsyncAppender 异步日志
- [x] 日志轮转（按大小）：`new_rolling_file_channel()` + `max_size_bytes` / `max_backups`
      （按时间轮转未做：`logrotate`/systemd 已覆盖，框架内再实现一遍会与外部轮转打架）
- [x] 运行时级别调整 + `/actuator/loggers`（`web/actuator_loggers.v`）
- [x] 结构化字段 API：`Logger.put/with_fields/named` + `LogContext`
- [x] `Logger.is_enabled(level)` 热路径守卫
- [x] 所有新增测试通过: `v test logger/`（`logger/rolling_test.v` 覆盖轮转与保留份数）

## Phase 9: 异常处理统一
- [x] ProblemDetail (RFC 7807) — `web/problem_detail.v`
- [ ] @[status_code] 注解
- [ ] 方法级 @[exception_handler]
- [ ] 异常处理链优先级
- [ ] 所有新增测试通过: `v test web/`

## Phase 10: 异步任务增强
- [ ] Future[T] 返回型异步
- [ ] AsyncContext 上下文传播
- [ ] 线程池监控 + /actuator/executor
- [ ] 所有新增测试通过: `v test async/`

## Phase 11: 服务发现
- [ ] ServiceRegistry 接口 + InMemory 实现
- [ ] LoadBalancer (RoundRobin/Random/Weighted)
- [ ] @[service_client] 声明式客户端
- [ ] 所有新增测试通过: `v test discovery/`

## Phase 12: HTTP 客户端
- [ ] 链式 API 构建
- [ ] ClientInterceptor 拦截器
- [ ] get_typed[T]() 类型化响应
- [ ] 所有新增测试通过: `v test http/`

## 跨模块契约修复（2026-07 补）
- [x] `security.CsrfManager`：token 收敛成集合，多标签页不再互相踢下线；
      `validate_any()` / `require_token()` 收掉「方法白名单 + 取值 + 校验」三件事；
      过滤器不再硬编码 `_csrf` 字段名
- [x] `queue.MemoryDriver.push_delayed()`：run_at 不再混进 payload，
      到期出队的 payload 与 `RedisDriver` 完全一致
- [x] 各模块测试文件重名用例（同模块内重复定义会导致整包编译失败）

## 全局验收
- [ ] `v test . -stats` 全部通过
- [ ] README.md 更新新注解列表和示例
- [ ] ARCHITECTURE.md 更新模块拓扑
- [ ] AGENTS.md 更新编码规范
- [ ] TUTORIAL.md 新增实战教程
- [ ] 无编译警告
- [ ] 无 unsafe 滥用（除 comptime 必需外）
