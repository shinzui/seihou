{-# LANGUAGE ImportQualifiedPost #-}

-- Run with: runghc -XGHC2024 -iseihou-core/src seihou-core/test/native/SeedExclusive.hs
-- Uses only GHC boot libraries, so the exact native implementation can also be
-- tested in a clean Linux compiler container without the application dependency graph.
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (bracket)
import Control.Monad (forM, forM_, unless)
import Data.ByteString.Char8 qualified as BS
import Seihou.Filesystem.Exclusive
import System.Directory qualified as D
import System.FilePath ((</>))
import System.IO (hClose, openBinaryTempFile)

check condition message = unless condition (ioError (userError message))

main :: IO ()
main = bracket setup D.removeDirectoryRecursive $ \root -> do
  let path = root </> "seed"
      publish text = createFileExclusiveWith (\handle -> BS.hPutStr handle (BS.pack text)) path
  publish "complete bytes\n" >>= \result -> check (result == ExclusiveCreated) "initial creation failed"
  publish "replacement" >>= \result -> check (result == ExclusiveOccupied) "replaced an existing file"
  BS.readFile path >>= \bytes -> check (bytes == BS.pack "complete bytes\n") "changed project bytes"
  D.removeFile path
  D.createFileLink "missing" path
  publish "replacement" >>= \result -> check (result == ExclusiveOccupied) "replaced a dangling symlink"
  D.getSymbolicLinkTarget path >>= \target -> check (target == "missing") "changed link target"
  D.removeFile path
  D.createDirectory path
  publish "replacement" >>= \result -> check (result == ExclusiveOccupied) "replaced a directory"
  D.removeDirectory path
  failed <- createFileExclusiveWith (\handle -> BS.hPutStr handle (BS.pack "partial") >> ioError (userError "injected write failure")) path
  check (case failed of ExclusiveFailure _ -> True; _ -> False) "partial failure was not reported"
  D.listDirectory root >>= \names -> check (null names) "partial write left a public or private entry"
  forM_ [1 .. 10 :: Int] $ \_ -> do
    results <- forM [1 .. 8 :: Int] $ \n -> do
      completed <- newEmptyMVar
      _ <- forkIO (publish (show n) >>= putMVar completed)
      pure completed
    outcomes <- mapM takeMVar results
    check (length (filter (== ExclusiveCreated) outcomes) == 1) "concurrent publication had multiple or no winners"
    check (length (filter (== ExclusiveOccupied) outcomes) == 7) "concurrent publication reported an unexpected error"
    D.removeFile path
  putStrLn "Native exclusive seed creation passed: complete bytes, occupied paths, partial failure and concurrent creators."
  where
    setup = do
      tmp <- D.getTemporaryDirectory
      (path, handle) <- openBinaryTempFile tmp "seed-exclusive-native"
      hClose handle
      D.removeFile path
      D.createDirectory path
      pure path
