module Test.Main where

import Prelude

import Data.Array as Data.Array
import Data.Foldable as Data.Foldable
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Console as Effect.Console
import Replay.Common as Replay.Common
import Replay.IdTranslation.Test as Replay.IdTranslation.Test
import Replay.PendingRequests.Test as Replay.PendingRequests.Test
import Replay.Player.Test as Replay.Player.Test
import Replay.Protocol.Types.Test as Replay.Protocol.Types.Test
import Replay.Recording.Test as Replay.Recording.Test
import Replay.Stream.Test as Replay.Stream.Test
import Replay.Test as Replay.Test
import Replay.TraceContext.Test as Replay.TraceContext.Test
import Replay.ULID.Test as Replay.ULID.Test

main :: Effect.Effect Unit
main = Effect.Aff.launchAff_ do
  Effect.Class.liftEffect $ Effect.Console.log "Running Replay unit tests...\n"

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.Test (Harness) ==="
  harnessResults <- Replay.Test.runTests
  Effect.Class.liftEffect $ printResults harnessResults

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.Player.Test ==="
  playerResults <- Replay.Player.Test.runTests
  Effect.Class.liftEffect $ printResults playerResults

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.IdTranslation.Test ==="
  let idTranslationResults = Replay.IdTranslation.Test.runTests
  Effect.Class.liftEffect $ printResults idTranslationResults

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.Recording.Test ==="
  recordingResults <- Replay.Recording.Test.runTests
  Effect.Class.liftEffect $ printResults recordingResults

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.Protocol.Types.Test ==="
  let protocolTypesResults = Replay.Protocol.Types.Test.runTests
  Effect.Class.liftEffect $ printResults protocolTypesResults

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.ULID.Test ==="
  ulidResults <- Effect.Class.liftEffect Replay.ULID.Test.runTests
  Effect.Class.liftEffect $ printResults ulidResults

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.Stream.Test ==="
  streamResults <- Effect.Class.liftEffect Replay.Stream.Test.runTests
  Effect.Class.liftEffect $ printResults streamResults

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.PendingRequests.Test ==="
  pendingRequestsResults <- Replay.PendingRequests.Test.runTests
  Effect.Class.liftEffect $ printResults pendingRequestsResults

  Effect.Class.liftEffect $ Effect.Console.log "=== Replay.TraceContext.Test ==="
  traceContextResults <- Effect.Class.liftEffect Replay.TraceContext.Test.runTests
  Effect.Class.liftEffect $ printResults traceContextResults

  let
    allResults =
      [ harnessResults
      , playerResults
      , idTranslationResults
      , recordingResults
      , protocolTypesResults
      , ulidResults
      , streamResults
      , pendingRequestsResults
      , traceContextResults
      ]
    totalPassed = Data.Array.foldl (\acc r -> acc + r.passed) 0 allResults
    totalFailed = Data.Array.foldl (\acc r -> acc + r.failed) 0 allResults
    totalTotal = Data.Array.foldl (\acc r -> acc + r.total) 0 allResults

  Effect.Class.liftEffect $ Effect.Console.log "\n======================================="
  Effect.Class.liftEffect $ Effect.Console.log "SUMMARY"
  Effect.Class.liftEffect $ Effect.Console.log "======================================="
  Effect.Class.liftEffect $ Effect.Console.log $ "Total: " <> show totalTotal <> " tests"
  Effect.Class.liftEffect $ Effect.Console.log $ "Passed: " <> show totalPassed
  Effect.Class.liftEffect $ Effect.Console.log $ "Failed: " <> show totalFailed

  when (totalFailed > 0) do
    Effect.Class.liftEffect $ Effect.Console.log "\nFailed tests:"
    Effect.Class.liftEffect $ Data.Foldable.for_ allResults printFailures

  if totalFailed > 0 then do
    Effect.Class.liftEffect $ Effect.Console.log "\nTESTS FAILED"
    Effect.Aff.throwError $ Effect.Aff.error "Tests failed"
  else
    Effect.Class.liftEffect $ Effect.Console.log "\nALL TESTS PASSED"

printResults :: Replay.Common.TestResults -> Effect.Effect Unit
printResults results = do
  Effect.Console.log $ "  Passed: " <> show results.passed <> "/" <> show results.total
  when (results.failed > 0) do
    Effect.Console.log $ "  Failed: " <> show results.failed

printFailures :: Replay.Common.TestResults -> Effect.Effect Unit
printFailures results =
  Data.Foldable.for_ results.failures printFailure
  where
  printFailure failure =
    Effect.Console.log $ "  - " <> failure.name <> ": " <> failure.reason
