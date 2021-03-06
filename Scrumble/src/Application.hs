{-# OPTIONS_GHC -fno-warn-orphans #-}
module Application
    ( makeApplication
    , getApplicationDev
    , makeFoundation
    ) where

import Import
import Settings
import Yesod.Auth
import Yesod.Default.Config
import Yesod.Default.Main
import Yesod.Default.Handlers
import Network.Wai.Middleware.RequestLogger
    ( mkRequestLogger, outputFormat, OutputFormat (..), IPAddrSource (..), destination
    )
import qualified Network.Wai.Middleware.RequestLogger as RequestLogger
import qualified Database.Persist
import Database.Persist.Sql (runMigration, runSqlPool)
import Network.HTTP.Conduit (newManager, conduitManagerSettings)
import qualified Network.Wai as W
import Network.Wai.Internal (Response (..))
import Network.HTTP.Types (status200)
import Control.Monad.Logger (runLoggingT)
import Control.Monad.Trans.Resource (runResourceT)
import Control.Concurrent (forkIO, threadDelay)
import System.Log.FastLogger (newStdoutLoggerSet, defaultBufSize)
import Network.Wai.Logger (clockDateCacher)
import Crypto.PasswordStore (makePassword)
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import Data.Default (def)
import Yesod.Core.Types (loggerSet, Logger (Logger))
import Handler.Home
import Handler.Users
import Handler.UsersUser
import Handler.Projects
import Handler.ProjectsProject
import Handler.ProjectUsers
import Handler.ProjectUser
import Handler.Authentication
import Handler.AuthLogout
import Handler.UsersUserPassword
import Handler.AuthUser
import Handler.Stories
import Handler.StoriesStory
import Handler.StoriesStoryNotes
import Handler.Sprint
import Handler.Sprints
import Handler.SprintStory
import Handler.SprintStories
import Handler.Tasks
import Handler.TasksTask
import Handler.ProjectDocs
import Handler.ProjectPosts
import Handler.Poker
import Model.Role

addCORS :: W.Middleware
addCORS app env = fmap updateHeaders (app env)
  where
    updateHeaders (ResponseFile    status headers fp mpart) = ResponseFile    status (new headers) fp mpart
    updateHeaders (ResponseBuilder status headers builder)  = ResponseBuilder status (new headers) builder
    updateHeaders (ResponseSource  status headers src)      = ResponseSource  status (new headers) src
    new headers = case lookup "Origin" (W.requestHeaders env) of
                Just origin -> [("Access-Control-Allow-Origin", origin), ("Access-Control-Allow-Credentials", "true")] ++ headers
                Nothing     -> headers

handleOptions :: W.Middleware
handleOptions app env =
    if W.requestMethod env == "OPTIONS"
        then return $ W.responseLBS status200 corsHeaders ""
        else app env

    where
        corsHeaders = [("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept"), 
                       ("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")]

-- This line actually creates our YesodDispatch instance. It is the second half
-- of the call to mkYesodData which occurs in Foundation.hs. Please see the
-- comments there for more details.
mkYesodDispatch "App" resourcesApp

-- This function allocates resources (such as a database connection pool),
-- performs initialization and creates a WAI application. This is also the
-- place to put your migrate statements to have automatic database
-- migrations handled by Yesod.
makeApplication :: AppConfig DefaultEnv Extra -> IO (Application, LogFunc)
makeApplication conf = do
    foundation <- makeFoundation conf

    -- Initialize the logging middleware
    logWare <- mkRequestLogger def
        { outputFormat =
            if development
                then Detailed True
                else Apache FromSocket
        , destination = RequestLogger.Logger $ loggerSet $ appLogger foundation
        }

    -- Create the WAI application and apply middlewares
    app <- toWaiAppPlain foundation
    let logFunc = messageLoggerSource foundation (appLogger foundation)
    return ((addCORS $ handleOptions $ logWare app), logFunc)

-- | Loads up any necessary settings, creates your foundation datatype, and
-- performs some initialization.
makeFoundation :: AppConfig DefaultEnv Extra -> IO App
makeFoundation conf = do
    manager <- newManager conduitManagerSettings
    s <- staticSite
    dbconf <- withYamlEnvironment "config/mysql.yml" (appEnv conf)
              Database.Persist.loadConfig >>=
              Database.Persist.applyEnv
    p <- Database.Persist.createPoolConfig (dbconf :: Settings.PersistConf)

    loggerSet' <- newStdoutLoggerSet defaultBufSize
    (getter, updater) <- clockDateCacher

    -- If the Yesod logger (as opposed to the request logger middleware) is
    -- used less than once a second on average, you may prefer to omit this
    -- thread and use "(updater >> getter)" in place of "getter" below.  That
    -- would update the cache every time it is used, instead of every second.
    let updateLoop = do
            threadDelay 1000000
            updater
            updateLoop
    _ <- forkIO updateLoop

    let logger = Yesod.Core.Types.Logger loggerSet' getter
        foundation = App conf s p manager dbconf logger

    -- Perform database migration using our application's logging settings.
    runLoggingT
        (Database.Persist.runPool dbconf (runMigration migrateAll) p)
        (messageLoggerSource foundation logger)

    let addTestUser = do
        _ <- insertBy $ User "test" "Test" "Test" "test@example.com" Administrator
        hashed <- liftIO $ decodeUtf8 `fmap` makePassword (encodeUtf8 "test") 14
        insertBy $ UserAuth "test" hashed

    _ <- runResourceT $ runLoggingT
        (runSqlPool addTestUser p)
        (messageLoggerSource foundation logger)

    return foundation

-- for yesod devel
getApplicationDev :: IO (Int, Application)
getApplicationDev =
    defaultDevelApp loader (fmap fst . makeApplication)
  where
    loader = Yesod.Default.Config.loadConfig (configSettings Development)
        { csParseExtra = parseExtra
        }
