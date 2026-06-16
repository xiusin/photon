module photon

// photon.v - Photon Framework Main Module
// A commercial-grade Spring-like application framework for V language
import config
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

// Re-export config types
pub type Config = config.Config

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

// Re-export CLI interactive & make commands
pub type AskResult = cli.AskResult
pub type ScheduleCommand = cli.ScheduleCommand
pub type QueueWorkCommand = cli.QueueWorkCommand
pub type MakeCommandCommand = cli.MakeCommandCommand
pub type MakeControllerCommand = cli.MakeControllerCommand
pub type MakeMiddlewareCommand = cli.MakeMiddlewareCommand
