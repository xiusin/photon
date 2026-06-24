# Spec — Photon 深度优化 v2

## 项目背景

Photon 是一个面向商业化应用的 V 语言企业级框架，对标 Spring Boot。当前版本 0.1.0 已完成：
- 16 个模块的初始实现（core, web, orm, cache, security, config, logger, async, queue, locking, pool, storage, ticker, http, support, i18n）
- P0-P2 安全修复、性能优化、代码质量改进（前序 3 轮优化已完成）
- 80+ 测试文件，覆盖核心功能

## 优化目标

参考 Spring Framework 6 和 Hyperf 3.1 的设计理念，对 Photon 进行深度架构优化，使其：
1. **更工程化**：接口分层、职责清晰、扩展点丰富
2. **更设计模式**：Builder、Strategy、Chain of Responsibility、Observer 等模式系统性应用
3. **高封装性**：低心智成本的 API，开发者无需理解内部实现
4. **易用性**：注解驱动、声明式编程、约定优于配置

## 设计原则

1. **不盲目开发**：每个改动必须参考 Spring/Hyperf 等价实现，且类比 Photon 现有实现
2. **向后兼容**：新增功能不破坏现有 API，废弃 API 通过 `@[deprecated]` 标注
3. **编译期优先**：利用 V comptime 实现零运行时反射
4. **测试先行**：每个 Task 必须包含测试用例，测试通过才算完成
5. **文档同步**：每个 Phase 完成后更新对应文档

## 对标框架

### Spring Framework 6 (Java)
- IoC: BeanFactory → ApplicationContext 层级，@Configuration/@Bean/@Conditional
- AOP: @Aspect/@Pointcut/@Around，JDK/CGLIB 代理
- ORM: Spring Data JPA, Specification, Pageable, @Query
- Web: Spring MVC, @RequestBody, ResponseEntity, HandlerInterceptor
- Cache: @Cacheable/@CacheEvict/@CachePut, CacheManager
- Events: ApplicationEvent<T>, @EventListener, @TransactionalEventListener
- Config: @ConfigurationProperties, Placeholder, Environment
- Exception: @ControllerAdvice, @ExceptionHandler, ProblemDetail

### Hyperf 3.1 (PHP)
- DI: PSR-11 容器，注解驱动注入，AOP 编译期织入
- Coroutine: Swoole/Swow 协程，连接池，上下文隔离
- Service: ServiceRegistry, LoadBalancer, @ServiceClient
- Config: ConfigProvider, env() 约定
- Events: PSR-14 事件管理器

## 实施约束

- V 语言版本: 0.5.x (weekly.2025.06+)
- 零外部依赖（仅 V 标准库 + crypto）
- 单二进制部署
- 内存安全（V 所有权系统）
- 编译期 DI（comptime $for）
