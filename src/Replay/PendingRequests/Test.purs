module Replay.PendingRequests.Test
  ( runTests
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Either as Data.Either
import Data.Int as Data.Int
import Data.Tuple as Data.Tuple
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Ref as Effect.Ref
import Foreign.Object as Foreign.Object
import Replay.Common as Replay.Common
import Replay.PendingRequests as Replay.PendingRequests
import Replay.Protocol.Types as Replay.Protocol.Types

makeStreamId :: String -> Replay.Protocol.Types.StreamId
makeStreamId = Replay.Protocol.Types.StreamId

makeObject :: Array (Data.Tuple.Tuple String Data.Argonaut.Core.Json) -> Data.Argonaut.Core.Json
makeObject pairs = Data.Argonaut.Core.fromObject (Foreign.Object.fromFoldable pairs)

makeTestResponse :: Int -> Replay.Protocol.Types.ResponsePayload
makeTestResponse statusCode =
  { service: "http"
  , payload: makeObject
      [ Data.Tuple.Tuple "statusCode" (Data.Argonaut.Core.fromNumber (Data.Int.toNumber statusCode))
      , Data.Tuple.Tuple "body" (Data.Argonaut.Core.fromString "test-response")
      ]
  }

testCreatePendingRequestsState :: Effect.Aff.Aff Replay.Common.TestResult
testCreatePendingRequestsState = do
  state <- Effect.Class.liftEffect Replay.PendingRequests.createPendingRequestsState
  count <- Effect.Class.liftEffect $ Replay.PendingRequests.getPendingCount state
  if count == 0 then
    pure $ Replay.Common.TestSuccess "createPendingRequestsState initializes with empty map"
  else
    pure $ Replay.Common.TestFailure "createPendingRequestsState initializes with empty map" ("Expected 0, got " <> show count)

testRegisterAndResolveRequest :: Effect.Aff.Aff Replay.Common.TestResult
testRegisterAndResolveRequest = do
  state <- Effect.Class.liftEffect Replay.PendingRequests.createPendingRequestsState
  resultRef <- Effect.Class.liftEffect $ Effect.Ref.new (Data.Either.Left Replay.PendingRequests.ConnectionClosed)

  let streamId = makeStreamId "test-stream-1"
  let expectedResponse = makeTestResponse 200

  let callback result = Effect.Ref.write result resultRef

  Effect.Class.liftEffect $ Replay.PendingRequests.registerRequest state streamId callback

  countAfterRegister <- Effect.Class.liftEffect $ Replay.PendingRequests.getPendingCount state
  resolved <- Effect.Class.liftEffect $ Replay.PendingRequests.resolveRequest state streamId expectedResponse
  countAfterResolve <- Effect.Class.liftEffect $ Replay.PendingRequests.getPendingCount state
  actualResult <- Effect.Class.liftEffect $ Effect.Ref.read resultRef

  if countAfterRegister == 1 && resolved && countAfterResolve == 0 && actualResult == Data.Either.Right expectedResponse then
    pure $ Replay.Common.TestSuccess "registerRequest and resolveRequest work correctly"
  else
    pure $ Replay.Common.TestFailure "registerRequest and resolveRequest work correctly"
      ( "countAfterRegister=" <> show countAfterRegister
          <> ", resolved="
          <> show resolved
          <> ", countAfterResolve="
          <> show countAfterResolve
      )

testResolveUnknownRequestReturnsFalse :: Effect.Aff.Aff Replay.Common.TestResult
testResolveUnknownRequestReturnsFalse = do
  state <- Effect.Class.liftEffect Replay.PendingRequests.createPendingRequestsState
  let streamId = makeStreamId "unknown-stream"
  let response = makeTestResponse 200

  resolved <- Effect.Class.liftEffect $ Replay.PendingRequests.resolveRequest state streamId response

  if not resolved then
    pure $ Replay.Common.TestSuccess "resolveRequest returns false for unknown streamId"
  else
    pure $ Replay.Common.TestFailure "resolveRequest returns false for unknown streamId" "Expected false, got true"

testResolveRequestWithError :: Effect.Aff.Aff Replay.Common.TestResult
testResolveRequestWithError = do
  state <- Effect.Class.liftEffect Replay.PendingRequests.createPendingRequestsState
  resultRef <- Effect.Class.liftEffect $ Effect.Ref.new (Data.Either.Right (makeTestResponse 0))

  let streamId = makeStreamId "test-stream-error"
  let expectedError = Replay.PendingRequests.RequestTimeout streamId

  let callback result = Effect.Ref.write result resultRef

  Effect.Class.liftEffect $ Replay.PendingRequests.registerRequest state streamId callback
  resolved <- Effect.Class.liftEffect $ Replay.PendingRequests.resolveRequestWithError state streamId expectedError
  actualResult <- Effect.Class.liftEffect $ Effect.Ref.read resultRef
  countAfterResolve <- Effect.Class.liftEffect $ Replay.PendingRequests.getPendingCount state

  if resolved && countAfterResolve == 0 && actualResult == Data.Either.Left expectedError then
    pure $ Replay.Common.TestSuccess "resolveRequestWithError works correctly"
  else
    pure $ Replay.Common.TestFailure "resolveRequestWithError works correctly"
      ("resolved=" <> show resolved <> ", countAfterResolve=" <> show countAfterResolve)

testCancelAllPending :: Effect.Aff.Aff Replay.Common.TestResult
testCancelAllPending = do
  state <- Effect.Class.liftEffect Replay.PendingRequests.createPendingRequestsState
  callCountRef <- Effect.Class.liftEffect $ Effect.Ref.new 0

  let
    callback _ = Effect.Ref.modify_ (_ + 1) callCountRef

  Effect.Class.liftEffect $ Replay.PendingRequests.registerRequest state (makeStreamId "stream-1") callback
  Effect.Class.liftEffect $ Replay.PendingRequests.registerRequest state (makeStreamId "stream-2") callback
  Effect.Class.liftEffect $ Replay.PendingRequests.registerRequest state (makeStreamId "stream-3") callback

  countBeforeCancel <- Effect.Class.liftEffect $ Replay.PendingRequests.getPendingCount state
  cancelledCount <- Effect.Class.liftEffect $ Replay.PendingRequests.cancelAllPending state Replay.PendingRequests.ConnectionClosed
  countAfterCancel <- Effect.Class.liftEffect $ Replay.PendingRequests.getPendingCount state
  callCount <- Effect.Class.liftEffect $ Effect.Ref.read callCountRef

  if countBeforeCancel == 3 && cancelledCount == 3 && countAfterCancel == 0 && callCount == 3 then
    pure $ Replay.Common.TestSuccess "cancelAllPending cancels all requests and invokes callbacks"
  else
    pure $ Replay.Common.TestFailure "cancelAllPending cancels all requests and invokes callbacks"
      ( "countBeforeCancel=" <> show countBeforeCancel
          <> ", cancelledCount="
          <> show cancelledCount
          <> ", countAfterCancel="
          <> show countAfterCancel
          <> ", callCount="
          <> show callCount
      )

testCancelAllPendingWithEmptyMap :: Effect.Aff.Aff Replay.Common.TestResult
testCancelAllPendingWithEmptyMap = do
  state <- Effect.Class.liftEffect Replay.PendingRequests.createPendingRequestsState

  cancelledCount <- Effect.Class.liftEffect $ Replay.PendingRequests.cancelAllPending state Replay.PendingRequests.ConnectionClosed

  if cancelledCount == 0 then
    pure $ Replay.Common.TestSuccess "cancelAllPending returns 0 for empty map"
  else
    pure $ Replay.Common.TestFailure "cancelAllPending returns 0 for empty map" ("Expected 0, got " <> show cancelledCount)

testMultipleRequestsDifferentStreamIds :: Effect.Aff.Aff Replay.Common.TestResult
testMultipleRequestsDifferentStreamIds = do
  state <- Effect.Class.liftEffect Replay.PendingRequests.createPendingRequestsState
  result1Ref <- Effect.Class.liftEffect $ Effect.Ref.new (Data.Either.Left Replay.PendingRequests.ConnectionClosed)
  result2Ref <- Effect.Class.liftEffect $ Effect.Ref.new (Data.Either.Left Replay.PendingRequests.ConnectionClosed)

  let streamId1 = makeStreamId "stream-1"
  let streamId2 = makeStreamId "stream-2"
  let response1 = makeTestResponse 200
  let response2 = makeTestResponse 201

  Effect.Class.liftEffect $ Replay.PendingRequests.registerRequest state streamId1 (Effect.Ref.write <@> result1Ref)
  Effect.Class.liftEffect $ Replay.PendingRequests.registerRequest state streamId2 (Effect.Ref.write <@> result2Ref)

  countAfterRegister <- Effect.Class.liftEffect $ Replay.PendingRequests.getPendingCount state

  _ <- Effect.Class.liftEffect $ Replay.PendingRequests.resolveRequest state streamId2 response2
  _ <- Effect.Class.liftEffect $ Replay.PendingRequests.resolveRequest state streamId1 response1

  actualResult1 <- Effect.Class.liftEffect $ Effect.Ref.read result1Ref
  actualResult2 <- Effect.Class.liftEffect $ Effect.Ref.read result2Ref
  countAfterResolve <- Effect.Class.liftEffect $ Replay.PendingRequests.getPendingCount state

  if
    countAfterRegister == 2
      && countAfterResolve == 0
      && actualResult1 == Data.Either.Right response1
      && actualResult2 == Data.Either.Right response2 then
    pure $ Replay.Common.TestSuccess "Multiple requests with different streamIds are tracked independently"
  else
    pure $ Replay.Common.TestFailure "Multiple requests with different streamIds are tracked independently"
      ( "countAfterRegister=" <> show countAfterRegister
          <> ", countAfterResolve="
          <> show countAfterResolve
      )

testRequestTimeoutError :: Effect.Aff.Aff Replay.Common.TestResult
testRequestTimeoutError = do
  let streamId = makeStreamId "timeout-stream"
  let timeoutError = Replay.PendingRequests.RequestTimeout streamId

  if show timeoutError == "RequestTimeout: \"timeout-stream\"" then
    pure $ Replay.Common.TestSuccess "RequestTimeout error shows streamId correctly"
  else
    pure $ Replay.Common.TestFailure "RequestTimeout error shows streamId correctly" ("Got: " <> show timeoutError)

testConnectionClosedError :: Effect.Aff.Aff Replay.Common.TestResult
testConnectionClosedError = do
  let error = Replay.PendingRequests.ConnectionClosed

  if show error == "ConnectionClosed" then
    pure $ Replay.Common.TestSuccess "ConnectionClosed error shows correctly"
  else
    pure $ Replay.Common.TestFailure "ConnectionClosed error shows correctly" ("Got: " <> show error)

testUnexpectedError :: Effect.Aff.Aff Replay.Common.TestResult
testUnexpectedError = do
  let error = Replay.PendingRequests.UnexpectedError "something went wrong"

  if show error == "UnexpectedError: something went wrong" then
    pure $ Replay.Common.TestSuccess "UnexpectedError shows message correctly"
  else
    pure $ Replay.Common.TestFailure "UnexpectedError shows message correctly" ("Got: " <> show error)

allTests :: Effect.Aff.Aff (Array Replay.Common.TestResult)
allTests = do
  r1 <- testCreatePendingRequestsState
  r2 <- testRegisterAndResolveRequest
  r3 <- testResolveUnknownRequestReturnsFalse
  r4 <- testResolveRequestWithError
  r5 <- testCancelAllPending
  r6 <- testCancelAllPendingWithEmptyMap
  r7 <- testMultipleRequestsDifferentStreamIds
  r8 <- testRequestTimeoutError
  r9 <- testConnectionClosedError
  r10 <- testUnexpectedError
  pure [ r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 ]

runTests :: Effect.Aff.Aff Replay.Common.TestResults
runTests = Replay.Common.computeResults <$> allTests
