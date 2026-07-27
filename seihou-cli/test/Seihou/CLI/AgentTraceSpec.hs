module Seihou.CLI.AgentTraceSpec (tests) where

import Baikai.Trace.Event (TraceEvent (..))
import Baikai.Trace.Sink (TraceSink (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Seihou.CLI.AgentCompletion (TraceSetting (..))
import Seihou.CLI.AgentTrace
  ( defaultTraceFileName,
    resolveTraceFilePath,
    traceSinkFor,
  )
import Streamly.Data.Stream qualified as Stream
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AgentTrace" spec

spec :: Spec
spec = do
  describe "resolveTraceFilePath" $ do
    it "falls back to the project-local default when nothing is configured" $
      resolveTraceFilePath Nothing `shouldBe` defaultTraceFileName

    it "puts the default inside .seihou/" $
      defaultTraceFileName `shouldBe` ".seihou" </> "trace.jsonl"

    it "uses an explicitly configured path" $
      resolveTraceFilePath (Just "/tmp/seihou-trace.jsonl") `shouldBe` "/tmp/seihou-trace.jsonl"

    -- Blank counts as absent everywhere else in the resolver; a blank
    -- agent.tracePath must not send the sink to "".
    it "treats a blank configured path as absent" $ do
      resolveTraceFilePath (Just "") `shouldBe` defaultTraceFileName
      resolveTraceFilePath (Just "   ") `shouldBe` defaultTraceFileName

  describe "traceSinkFor" $ do
    it "writes nothing anywhere when tracing is off" $
      withSystemTempDirectory "seihou-trace-off" $ \root -> do
        sink <- traceSinkFor TraceOff (Just (root </> "nested" </> "trace.jsonl"))
        feed sink [startEvent]
        doesDirectoryExist (root </> "nested") `shouldReturn` False

    it "creates the trace file's parent directory" $
      withSystemTempDirectory "seihou-trace-mkdir" $ \root -> do
        let path = root </> "deeply" </> "nested" </> "trace.jsonl"
        _ <- traceSinkFor TraceFile (Just path)
        doesDirectoryExist (root </> "deeply" </> "nested") `shouldReturn` True

    it "appends one parseable JSON object per event" $
      withSystemTempDirectory "seihou-trace-file" $ \root -> do
        let path = root </> "trace.jsonl"
        sink <- traceSinkFor TraceFile (Just path)
        feed sink [startEvent, finishEvent]
        contents <- BL8.readFile path
        let ls = filter (not . BL8.null) (BL8.lines contents)
        length ls `shouldBe` 2
        traverse (Aeson.decode @Aeson.Value) ls `shouldSatisfy` \case
          Just _ -> True
          Nothing -> False

    it "tags each line with the event kind that jq filters on" $
      withSystemTempDirectory "seihou-trace-kind" $ \root -> do
        let path = root </> "trace.jsonl"
        sink <- traceSinkFor TraceFile (Just path)
        feed sink [startEvent, finishEvent]
        kinds <- traceKinds path
        kinds `shouldBe` ["call_started", "call_finished"]

    it "correlates a start and its finish by eventId" $
      withSystemTempDirectory "seihou-trace-corr" $ \root -> do
        let path = root </> "trace.jsonl"
        sink <- traceSinkFor TraceFile (Just path)
        feed sink [startEvent, finishEvent]
        ids <- traceField "eventId" path
        ids `shouldBe` ["call-1", "call-1"]

    it "records a failure as call_failed" $
      withSystemTempDirectory "seihou-trace-fail" $ \root -> do
        let path = root </> "trace.jsonl"
        sink <- traceSinkFor TraceFile (Just path)
        feed sink [startEvent, failEvent]
        traceKinds path `shouldReturn` ["call_started", "call_failed"]

    -- The file sink appends rather than truncating, so a second traced run in
    -- the same project accumulates history instead of destroying it.
    it "appends across separately constructed sinks" $
      withSystemTempDirectory "seihou-trace-append" $ \root -> do
        let path = root </> "trace.jsonl"
        first <- traceSinkFor TraceFile (Just path)
        feed first [startEvent, finishEvent]
        second <- traceSinkFor TraceFile (Just path)
        feed second [startEvent, finishEvent]
        kinds <- traceKinds path
        length kinds `shouldBe` 4

    it "creates no file for the stream settings" $
      withSystemTempDirectory "seihou-trace-stream" $ \root -> do
        let path = root </> "trace.jsonl"
        stderrOnly <- traceSinkFor TraceStderr (Just path)
        _ <- pure stderrOnly
        doesFileExist path `shouldReturn` False

-- | Drive a sink's fold over a list of events, the way Baikai's trace bridge
-- drives it over the per-call event channel.
feed :: TraceSink -> [TraceEvent] -> IO ()
feed (TraceSink f) events = Stream.fold f (Stream.fromList events)

-- | The @kind@ tag of every line in a JSONL trace file, in order.
traceKinds :: FilePath -> IO [String]
traceKinds = traceField "kind"

-- | One top-level string field from every line of a JSONL trace file.
traceField :: String -> FilePath -> IO [String]
traceField field path = do
  contents <- BL8.readFile path
  pure
    [ Text.unpack value
    | line <- BL8.lines contents,
      not (BL8.null line),
      Just (Aeson.Object o) <- [Aeson.decode line],
      Just (Aeson.String value) <- [KeyMap.lookup (Key.fromString field) o]
    ]

at :: UTCTime
at = UTCTime (fromGregorian 2026 7 27) (secondsToDiffTime 0)

startEvent :: TraceEvent
startEvent =
  CallStarted
    { eventId = "call-1",
      timestamp = at,
      provider = "anthropic",
      model = "claude-sonnet-4-6",
      maxTokens = 8192,
      promptSummary = "add a health check module"
    }

finishEvent :: TraceEvent
finishEvent =
  CallFinished
    { eventId = "call-1",
      timestamp = at,
      provider = "anthropic",
      model = "claude-sonnet-4-6",
      latencyMs = 7913,
      inputTokens = Just 4211,
      outputTokens = Just 880,
      usd = Just 0.0264
    }

failEvent :: TraceEvent
failEvent =
  CallFailed
    { eventId = "call-1",
      timestamp = at,
      provider = "anthropic",
      model = "claude-sonnet-4-6",
      latencyMs = 120,
      errorMessage = "invalid x-api-key"
    }
