{-# LANGUAGE GeneralizedNewtypeDeriving, DeriveDataTypeable, Rank2Types, ScopedTypeVariables, ViewPatterns #-}
{-# LANGUAGE TypeFamilies #-}

-- | A module for producing forward-defined build systems, in contrast to standard backwards-defined
--   build systems such as shake. Based around ideas from <https://code.google.com/p/fabricate/ fabricate>.
--   As an example:
--
-- @
-- import "Development.Shake"
-- import "Development.Shake.Forward"
-- import "Development.Shake.FilePath"
--
-- main = 'shakeArgsForward' 'shakeOptions' $ do
--     contents <- 'readFileLines' \"result.txt\"
--     'cache' $ 'cmd' \"tar -cf result.tar\" contents
-- @
--
--   Compared to backward-defined build systems (such as normal Shake), forward-defined build
--   systems tend to be simpler for simple systems (less boilerplate, more direct style), but more
--   complex for larger build systems (requires explicit parallelism, explicit sharing of build products,
--   no automatic command line targets). As a general approach for writing forward-defined systems:
--
-- * Figure out the sequence of system commands that will build your project.
--
-- * Write a simple 'Action' that builds your project.
--
-- * Insert 'cache' in front of most system commands.
--
-- * Replace most loops with 'forP', where they can be executed in parallel.
--
-- * Where Haskell performs real computation, if zero-build performance is insufficient, use 'cacheAction'.
--
--   All forward-defined systems use 'AutoDeps', which requires @fsatrace@ to be on the @$PATH@.
--   You can obtain @fsatrace@ from <https://github.com/jacereda/fsatrace>.
--
--   This module is considered experimental - it has not been battle tested.
--   A possible alternative is available at <http://hackage.haskell.org/package/pier/docs/Pier-Core-Artifact.html>.
module Development.Shake.Forward(
    shakeForward, shakeArgsForward,
    forwardOptions, forwardRule,
    cache, cacheAction
    ) where

import Development.Shake
import Development.Shake.Rule
import Development.Shake.Command
import Development.Shake.Classes
import Development.Shake.FilePath
import Data.IORef
import Data.Either
import Data.Typeable
import Data.List.Extra
import Control.Exception.Extra
import Numeric
import System.IO.Unsafe
import Data.Binary
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.HashMap.Strict as Map


{-# NOINLINE forwards #-}
forwards :: IORef (Map.HashMap Forward (Action Forward))
forwards = unsafePerformIO $ newIORef Map.empty

-- I'd like to use TypeRep, but it doesn't have any instances in older versions
newtype Forward = Forward (String, String, BS.ByteString) -- the type, the Show, the payload
    deriving (Hashable,Typeable,Eq,NFData,Binary)

mkForward :: (Typeable a, Show a, Binary a) => a -> Forward
mkForward x = Forward (show $ typeOf x, show x, encode' x)

unForward :: forall a . (Typeable a, Show a, Binary a) => Forward -> a
unForward (Forward (got,_,x))
    | got /= want = error $ "Failed to match forward type, wanted " ++ show want ++ ", got " ++ show got
    | otherwise = decode' x
    where want = show $ typeRep (Proxy :: Proxy a)

encode' :: Binary a => a -> BS.ByteString
encode' = BS.concat . LBS.toChunks . encode

decode' :: Binary a => BS.ByteString -> a
decode' = decode . LBS.fromChunks . return

type instance RuleResult Forward = Forward

instance Show Forward where
    show (Forward (_,x,_)) = x

-- | Run a forward-defined build system.
shakeForward :: ShakeOptions -> Action () -> IO ()
shakeForward opts act = shake (forwardOptions opts) (forwardRule act)

-- | Run a forward-defined build system, interpreting command-line arguments.
shakeArgsForward :: ShakeOptions -> Action () -> IO ()
shakeArgsForward opts act = shakeArgs (forwardOptions opts) (forwardRule act)

-- | Given an 'Action', turn it into a 'Rules' structure which runs in forward mode.
forwardRule :: Action () -> Rules ()
forwardRule act = do
    addBuiltinRule noLint noIdentity $ \k old mode ->
        case old of
            Just old | mode == RunDependenciesSame -> return $ RunResult ChangedNothing old (decode' old)
            _ -> do
                res <- liftIO $ atomicModifyIORef forwards $ \mp -> (Map.delete k mp, Map.lookup k mp)
                case res of
                    Nothing -> liftIO $ errorIO $ "Failed to find action name, " ++ show k
                    Just act -> do
                        new <- act
                        return $ RunResult ChangedRecomputeSame (encode' new) new
    action act

-- | Given a 'ShakeOptions', set the options necessary to execute in forward mode.
forwardOptions :: ShakeOptions -> ShakeOptions
forwardOptions opts = opts{shakeCommandOptions=[AutoDeps]}


-- | Cache an action. The name of the action must be unique for all different actions.
cacheAction :: (Typeable a, Binary a, Show a, Typeable b, Binary b, Show b) => a -> Action b -> Action b
cacheAction (mkForward -> key) (action :: Action b) = do
    liftIO $ atomicModifyIORef forwards $ \mp -> (Map.insert key (mkForward <$> action) mp, ())
    res <- apply1 key
    liftIO $ atomicModifyIORef forwards $ \mp -> (Map.delete key mp, ())
    return $ unForward res

-- | Apply caching to an external command.
cache :: (forall r . CmdArguments r => r) -> Action ()
cache cmd = do
    let CmdArgument args = cmd
    let isDull ['-',_] = True; isDull _ = False
    let name = head $ filter (not . isDull) (drop 1 $ rights args) ++ ["unknown"]
    cacheAction (Command $ toStandard name ++ " #" ++ upper (showHex (abs $ hash $ show args) "")) cmd

newtype Command = Command String
    deriving (Typeable, Binary)

instance Show Command where
    show (Command x) = "command " ++ x
