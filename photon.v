module photon

// photon.v - Photon Framework Main Module
// A commercial-grade Spring-like application framework for V language
import config
import core
import logger
import cache
import security
import cli
import ticker
import support
import http
import queue
import locking
import orm
import web
import storage
import mailer
import apidoc

// Re-export config types
pub type Config = config.Config

// Re-export core types (DI Container + Event System + Lifecycle)
pub type Container = core.Container
pub type BeanDefinition = core.BeanDefinition
pub type Scope = core.Scope
pub type Dependency = core.Dependency
pub type EventBus = core.EventBus
pub type Event = core.Event
pub type LifecycleManager = core.LifecycleManager
pub type ConditionContext = core.ConditionContext

// Re-export core scanner types
pub type ComponentType = core.ComponentType
pub type ScannedBean = core.ScannedBean
pub type ValueBinding = core.ValueBinding

// Re-export logger types
pub type Logger = logger.Logger
pub type ChannelLogger = logger.ChannelLogger

// Re-export cache types
pub type CacheManager = cache.CacheManager

// Re-export security types
pub type JwtManager = security.JwtManager
pub type AuthenticationManager = security.AuthenticationManager
pub type SecurityFilterChain = security.SecurityFilterChain
pub type CsrfManager = security.CsrfManager
pub type SecurityContext = security.SecurityContext
pub type RoleHierarchy = security.RoleHierarchy
pub type UserDetails = security.UserDetails
pub type Encrypter = security.Encrypter
pub type BcryptHasher = security.BcryptHasher
pub type Argon2Hasher = security.Argon2Hasher

// Re-export cli types
pub type CliApplication = cli.CliApplication
pub type Command = cli.Command
pub type CommandInput = cli.CommandInput
pub type CommandOutput = cli.CommandOutput

// Re-export ticker types
pub type Timer = ticker.Timer
pub type Ticker = ticker.Ticker

// Re-export support types (generic — use with type param, e.g. Collection[int])
// pub type Collection = support.Collection
// pub type LengthAwarePaginator = support.LengthAwarePaginator
// pub type SimplePaginator = support.SimplePaginator

// Re-export http types
pub type HttpClient = http.HttpClient
pub type HttpResponse = http.HttpResponse

// Re-export queue types
pub type Job = queue.Job
pub type QueueDispatcher = queue.QueueDispatcher
pub type MemoryDriver = queue.MemoryDriver

// Re-export sort types
pub type Sort = support.Sort
pub type PageRequest = support.PageRequest

// Re-export orm types
pub type OrmManager = orm.OrmManager
pub type DriverType = orm.DriverType
pub type TransactionManager = orm.TransactionManager
pub type Propagation = orm.Propagation
pub type QueryParts = orm.QueryParts
pub type Repository = orm.Repository

// Re-export orm migration types
pub type MigrationManager = orm.MigrationManager
pub type Schema = orm.Schema
pub type TableDef = orm.TableDef
pub type ColumnDef = orm.ColumnDef
pub type ColumnType = orm.ColumnType
pub type IndexDef = orm.IndexDef
pub type AppliedMigration = orm.AppliedMigration

// Re-export orm adapter types (generic — use with type param)
// pub type OrmAdapter = orm.OrmAdapter

// Re-export config environment types
pub type Environment = config.Environment

// Re-export locking types
pub type LockGuard = locking.LockGuard
pub type LockManager = locking.LockManager

// Re-export queue failed job types
pub type FailedJob = queue.FailedJob
pub type FailedJobRepository = queue.FailedJobRepository
pub type FailedJobHandler = queue.FailedJobHandler

// Re-export web middleware group types
pub type MiddlewareGroupRegistry = web.MiddlewareGroupRegistry
pub type ModelBindingRegistry = web.ModelBindingRegistry

// Re-export cache tags & locks
pub type TaggedCache = cache.TaggedCache
pub type CacheLock = cache.CacheLock

// Re-export storage types
pub type StorageManager = storage.StorageManager
pub type LocalAdapter = storage.LocalAdapter
pub type S3Adapter = storage.S3Adapter
pub type FileMetadata = storage.FileMetadata

// Re-export web testing helpers
pub type TestResponse = web.TestResponse

// Re-export web validation types
pub type ValidationError = web.ValidationError
pub type ValidationErrors = web.ValidationErrors

// Re-export web exception types
pub type HttpException = web.HttpException
pub type BadRequestException = web.BadRequestException
pub type UnauthorizedException = web.UnauthorizedException
pub type ForbiddenException = web.ForbiddenException
pub type NotFoundException = web.NotFoundException
pub type ConflictException = web.ConflictException
pub type ValidationException = web.ValidationException
pub type InternalServerErrorException = web.InternalServerErrorException
pub type ExceptionHandlerRegistry = web.ExceptionHandlerRegistry

// Re-export CLI interactive & make commands
pub type AskResult = cli.AskResult
pub type ScheduleCommand = cli.ScheduleCommand
pub type QueueWorkCommand = cli.QueueWorkCommand
pub type MakeCommandCommand = cli.MakeCommandCommand
pub type MakeControllerCommand = cli.MakeControllerCommand
pub type MakeMiddlewareCommand = cli.MakeMiddlewareCommand

// Re-export scheduler types (P1)
pub type Scheduler = ticker.Scheduler
pub type ScheduledTask = ticker.ScheduledTask
pub type TaskScheduleType = ticker.TaskScheduleType

// Re-export transaction annotation types (P1)
pub type TransactionAttribute = orm.TransactionAttribute
pub type TransactionContext = orm.TransactionContext
pub type TransactionalInterceptor = orm.TransactionalInterceptor

// Re-export cache annotation types (P1)
pub type CacheableAttribute = cache.CacheableAttribute
pub type CacheEvictAttribute = cache.CacheEvictAttribute
pub type CachePutAttribute = cache.CachePutAttribute
pub type CacheableInterceptor = cache.CacheableInterceptor

// Re-export session types (P1)
pub type Session = web.Session
pub type SessionManager = web.SessionManager
pub type MemorySessionStore = web.MemorySessionStore

// Re-export upload types (P1)
pub type UploadHandler = web.UploadHandler
pub type UploadResult = web.UploadResult
pub type NamingStrategy = web.NamingStrategy
pub type PathStrategy = web.PathStrategy
pub type UploadChunkManager = web.UploadChunkManager

// Re-export mailer types (P1)
pub type Mailer = mailer.Mailer
pub type Mail = mailer.Email
pub type SmtpConfig = mailer.SmtpConfig
pub type Address = mailer.Address

// Re-export cipher types (P1)
pub type AesCipher = security.AesCipher
pub type KeyDerivation = security.KeyDerivation

// Re-export YAML/TOML config source types (P1)
pub type YamlConfigSource = config.YamlConfigSource
pub type TomlConfigSource = config.TomlConfigSource

// Re-export apidoc types (API documentation collector + handler)
pub type ApidocHandler = apidoc.ApidocHandler
pub type Collector = apidoc.Collector
pub type ApiDocStore = apidoc.ApiDocStore
pub type ApiDocEntry = apidoc.ApiDocEntry
pub type ApiDocRequest = apidoc.ApiDocRequest
pub type ApiDocResponse = apidoc.ApiDocResponse
pub type ApiDocParam = apidoc.ApiDocParam
pub type ApiDocHeader = apidoc.ApiDocHeader
pub type ApiDocResponseProp = apidoc.ApiDocResponseProp
