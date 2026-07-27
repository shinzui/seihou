-- | Turning a resolved 'TraceSetting' into a live Baikai 'TraceSink'.
--
-- This is the only module in Seihou that touches the filesystem on behalf of
-- tracing (it creates the trace file's parent directory) and the only one that
-- imports "Baikai.Trace.Sink". Keeping it separate from
-- "Seihou.CLI.AgentCompletion" keeps sink construction — which is effectful —
-- out of the pure resolution path.
module Seihou.CLI.AgentTrace
  ( traceSinkForConfig,
    traceSinkFor,
    resolveTraceFilePath,
    defaultTraceFileName,
    stderrSink,
  )
where

import Baikai.Trace.Sink (TraceSink (..), fileSink, renderHuman, silent, stdoutSink)
import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion (AgentModelConfig (..), TraceSetting (..), traceToText)
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Types (LogLevel)
import Seihou.Effect.Logger (logInfo)
import Seihou.Prelude
import Streamly.Data.Fold qualified as Fold
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)
import System.IO (stderr)

-- | Where the file sink writes when @agent.tracePath@ is unset:
-- @.seihou/trace.jsonl@, beside the manifest and project config that Seihou
-- already keeps there.
defaultTraceFileName :: FilePath
defaultTraceFileName = ".seihou" </> "trace.jsonl"

-- | The configured @agent.tracePath@ when set and non-blank, otherwise
-- 'defaultTraceFileName'. A whitespace-only path counts as absent, matching
-- the resolver's treatment of every other setting.
resolveTraceFilePath :: Maybe FilePath -> FilePath
resolveTraceFilePath configured =
  case configured of
    Just raw | not (T.null (T.strip (T.pack raw))) -> raw
    _ -> defaultTraceFileName

-- | Print each event to stderr using Baikai's 'renderHuman'.
--
-- Baikai ships 'stdoutSink' but no stderr equivalent, and stderr is where
-- Seihou already sends out-of-band information (see
-- "Seihou.Effect.LoggerInterp"), so trace lines never corrupt assistant output
-- a user is piping.
stderrSink :: TraceSink
stderrSink = TraceSink (Fold.drainMapM (TIO.hPutStrLn stderr . renderHuman))

-- | Build the sink a resolved trace setting names.
--
-- 'TraceOff' yields Baikai's 'silent' sink, which discards every event — that
-- is the default, and it is what keeps tracing free when nobody asked for it.
-- 'TraceFile' creates the trace file's parent directory first, so the first
-- traced run in a project without a @.seihou/@ directory succeeds.
traceSinkFor :: TraceSetting -> Maybe FilePath -> IO TraceSink
traceSinkFor setting configuredPath =
  case setting of
    TraceOff -> pure silent
    TraceStdout -> pure stdoutSink
    TraceStderr -> pure stderrSink
    TraceFile -> do
      let path = resolveTraceFilePath configuredPath
      createDirectoryIfMissing True (takeDirectory path)
      fileSink path

-- | Build the sink a resolved agent configuration asks for, naming the
-- destination at verbose level.
--
-- Call this once per command rather than once per model call, so a command
-- that makes several calls — @seihou agent migrate@ walks one call per
-- migration edge — reports one destination and appends every call to it.
traceSinkForConfig :: LogLevel -> AgentModelConfig -> IO TraceSink
traceSinkForConfig level config = do
  case config ^. #trace of
    TraceOff -> pure ()
    TraceFile ->
      logIO level $
        logInfo ("Trace: writing call traces to " <> T.pack (resolveTraceFilePath (config ^. #tracePath)))
    other ->
      logIO level (logInfo ("Trace: writing call traces to " <> traceToText other))
  traceSinkFor (config ^. #trace) (config ^. #tracePath)
