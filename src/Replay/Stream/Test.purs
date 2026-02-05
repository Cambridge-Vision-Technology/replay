module Replay.Stream.Test
  ( runTests
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Maybe as Data.Maybe
import Data.String as Data.String
import Data.Tuple as Data.Tuple
import Effect as Effect
import Foreign.Object as Foreign.Object
import Json.Nullable as Json.Nullable
import Replay.Common as Replay.Common
import Replay.Stream as Replay.Stream
import Replay.TraceContext as Replay.TraceContext
import Replay.Protocol.Types as Replay.Protocol.Types

-- | Helper to create JSON object
makeObject :: Array (Data.Tuple.Tuple String Data.Argonaut.Core.Json) -> Data.Argonaut.Core.Json
makeObject pairs = Data.Argonaut.Core.fromObject (Foreign.Object.fromFoldable pairs)

sampleBamlRequest :: Replay.Protocol.Types.RequestPayload
sampleBamlRequest =
  { service: "baml"
  , payload: makeObject
      [ Data.Tuple.Tuple "functionName" (Data.Argonaut.Core.fromString "TestFunction")
      , Data.Tuple.Tuple "args" (makeObject [ Data.Tuple.Tuple "input" (Data.Argonaut.Core.fromString "test") ])
      , Data.Tuple.Tuple "options" Data.Argonaut.Core.jsonNull
      , Data.Tuple.Tuple "templateHash" (Data.Argonaut.Core.fromString "abc123")
      ]
  }

sampleBamlResponse :: Replay.Protocol.Types.ResponsePayload
sampleBamlResponse =
  { service: "baml"
  , payload: makeObject
      [ Data.Tuple.Tuple "result" (makeObject [ Data.Tuple.Tuple "output" (Data.Argonaut.Core.fromString "test result") ])
      , Data.Tuple.Tuple "thinking" (Data.Argonaut.Core.fromString "I analyzed the input")
      , Data.Tuple.Tuple "prompt" (Data.Argonaut.Core.fromString "Process this input")
      ]
  }

unwrapEnvelope :: forall a. Replay.Protocol.Types.Envelope a -> { streamId :: Replay.Protocol.Types.StreamId, traceId :: Replay.Protocol.Types.TraceId, causationStreamId :: Json.Nullable.JsonNullable Replay.Protocol.Types.StreamId, parentStreamId :: Json.Nullable.JsonNullable Replay.Protocol.Types.StreamId, siblingIndex :: Replay.Protocol.Types.SiblingIndex, eventSeq :: Replay.Protocol.Types.EventSeq, timestamp :: String, channel :: Replay.Protocol.Types.Channel, payloadHash :: Data.Maybe.Maybe String, payload :: a }
unwrapEnvelope (Replay.Protocol.Types.Envelope env) = env

testCreateOpenEventHasEventSeqZero :: Effect.Effect Replay.Common.TestResult
testCreateOpenEventHasEventSeqZero = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  pure $
    if env.eventSeq == Replay.Protocol.Types.EventSeq 0 then
      Replay.Common.TestSuccess "createOpenEvent creates envelope with eventSeq 0"
    else
      Replay.Common.TestFailure "createOpenEvent creates envelope with eventSeq 0" ("Expected EventSeq 0, got " <> show env.eventSeq)

testCreateCloseEventHasEventSeqOne :: Effect.Effect Replay.Common.TestResult
testCreateCloseEventHasEventSeqOne = do
  ctx <- Replay.TraceContext.newTrace
  let streamId = Replay.TraceContext.currentStreamId ctx
  closeEvent <- Replay.Stream.createCloseEvent ctx streamId Replay.Protocol.Types.ProgramChannel sampleBamlResponse
  let env = unwrapEnvelope closeEvent
  pure $
    if env.eventSeq == Replay.Protocol.Types.EventSeq 1 then
      Replay.Common.TestSuccess "createCloseEvent creates envelope with eventSeq 1"
    else
      Replay.Common.TestFailure "createCloseEvent creates envelope with eventSeq 1" ("Expected EventSeq 1, got " <> show env.eventSeq)

testOpenAndCloseEventsHaveMatchingStreamId :: Effect.Effect Replay.Common.TestResult
testOpenAndCloseEventsHaveMatchingStreamId = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let openEnv = unwrapEnvelope openEvent
  let streamId = openEnv.streamId
  closeEvent <- Replay.Stream.createCloseEvent ctx streamId Replay.Protocol.Types.ProgramChannel sampleBamlResponse
  let closeEnv = unwrapEnvelope closeEvent
  pure $
    if openEnv.streamId == closeEnv.streamId then
      Replay.Common.TestSuccess "Open and close events have matching streamId"
    else
      Replay.Common.TestFailure "Open and close events have matching streamId" ("Open streamId: " <> show openEnv.streamId <> ", Close streamId: " <> show closeEnv.streamId)

testTraceIdPropagatedToOpenEvent :: Effect.Effect Replay.Common.TestResult
testTraceIdPropagatedToOpenEvent = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  pure $
    if env.traceId == Replay.TraceContext.traceId ctx then
      Replay.Common.TestSuccess "TraceContext traceId is correctly propagated to open envelope"
    else
      Replay.Common.TestFailure "TraceContext traceId is correctly propagated to open envelope" "traceId mismatch"

testTraceIdPropagatedToCloseEvent :: Effect.Effect Replay.Common.TestResult
testTraceIdPropagatedToCloseEvent = do
  ctx <- Replay.TraceContext.newTrace
  let streamId = Replay.TraceContext.currentStreamId ctx
  closeEvent <- Replay.Stream.createCloseEvent ctx streamId Replay.Protocol.Types.ProgramChannel sampleBamlResponse
  let env = unwrapEnvelope closeEvent
  pure $
    if env.traceId == Replay.TraceContext.traceId ctx then
      Replay.Common.TestSuccess "TraceContext traceId is correctly propagated to close envelope"
    else
      Replay.Common.TestFailure "TraceContext traceId is correctly propagated to close envelope" "traceId mismatch"

testCurrentStreamIdUsedForOpenEvent :: Effect.Effect Replay.Common.TestResult
testCurrentStreamIdUsedForOpenEvent = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  pure $
    if env.streamId == Replay.TraceContext.currentStreamId ctx then
      Replay.Common.TestSuccess "TraceContext currentStreamId is used for open event streamId"
    else
      Replay.Common.TestFailure "TraceContext currentStreamId is used for open event streamId" "streamId does not match currentStreamId"

testSiblingIndexPropagatedToOpenEvent :: Effect.Effect Replay.Common.TestResult
testSiblingIndexPropagatedToOpenEvent = do
  ctx <- Replay.TraceContext.newTrace
  sibling <- Replay.TraceContext.siblingContext ctx (Replay.Protocol.Types.SiblingIndex 3)
  openEvent <- Replay.Stream.createOpenEvent sibling Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  pure $
    if env.siblingIndex == Replay.Protocol.Types.SiblingIndex 3 then
      Replay.Common.TestSuccess "TraceContext siblingIndex is propagated to open envelope"
    else
      Replay.Common.TestFailure "TraceContext siblingIndex is propagated to open envelope" ("Expected SiblingIndex 3, got " <> show env.siblingIndex)

testSiblingIndexPropagatedToCloseEvent :: Effect.Effect Replay.Common.TestResult
testSiblingIndexPropagatedToCloseEvent = do
  ctx <- Replay.TraceContext.newTrace
  sibling <- Replay.TraceContext.siblingContext ctx (Replay.Protocol.Types.SiblingIndex 5)
  let streamId = Replay.TraceContext.currentStreamId sibling
  closeEvent <- Replay.Stream.createCloseEvent sibling streamId Replay.Protocol.Types.ProgramChannel sampleBamlResponse
  let env = unwrapEnvelope closeEvent
  pure $
    if env.siblingIndex == Replay.Protocol.Types.SiblingIndex 5 then
      Replay.Common.TestSuccess "TraceContext siblingIndex is propagated to close envelope"
    else
      Replay.Common.TestFailure "TraceContext siblingIndex is propagated to close envelope" ("Expected SiblingIndex 5, got " <> show env.siblingIndex)

testParentStreamIdPropagatedToOpenEvent :: Effect.Effect Replay.Common.TestResult
testParentStreamIdPropagatedToOpenEvent = do
  root <- Replay.TraceContext.newTrace
  child <- Replay.TraceContext.childContext root
  openEvent <- Replay.Stream.createOpenEvent child Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  let expectedParentId = Data.Maybe.Just (Replay.TraceContext.currentStreamId root)
  let actualParentId = Json.Nullable.jsonNullableToMaybe env.parentStreamId
  pure $
    if actualParentId == expectedParentId then
      Replay.Common.TestSuccess "TraceContext parentStreamId is propagated to open envelope"
    else
      Replay.Common.TestFailure "TraceContext parentStreamId is propagated to open envelope" "parentStreamId mismatch"

testCausationStreamIdPropagatedToOpenEvent :: Effect.Effect Replay.Common.TestResult
testCausationStreamIdPropagatedToOpenEvent = do
  ctx <- Replay.TraceContext.newTrace
  let causationId = Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  let ctxWithCausation = Replay.TraceContext.withCausation causationId ctx
  openEvent <- Replay.Stream.createOpenEvent ctxWithCausation Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  let actualCausationId = Json.Nullable.jsonNullableToMaybe env.causationStreamId
  pure $
    if actualCausationId == Data.Maybe.Just causationId then
      Replay.Common.TestSuccess "TraceContext causationStreamId is propagated to open envelope"
    else
      Replay.Common.TestFailure "TraceContext causationStreamId is propagated to open envelope" "causationStreamId mismatch"

testTimestampPopulatedInOpenEvent :: Effect.Effect Replay.Common.TestResult
testTimestampPopulatedInOpenEvent = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  pure $
    if Data.String.length env.timestamp > 0 then
      Replay.Common.TestSuccess "Timestamp is populated in open event"
    else
      Replay.Common.TestFailure "Timestamp is populated in open event" "timestamp is empty"

testTimestampPopulatedInCloseEvent :: Effect.Effect Replay.Common.TestResult
testTimestampPopulatedInCloseEvent = do
  ctx <- Replay.TraceContext.newTrace
  let streamId = Replay.TraceContext.currentStreamId ctx
  closeEvent <- Replay.Stream.createCloseEvent ctx streamId Replay.Protocol.Types.ProgramChannel sampleBamlResponse
  let env = unwrapEnvelope closeEvent
  pure $
    if Data.String.length env.timestamp > 0 then
      Replay.Common.TestSuccess "Timestamp is populated in close event"
    else
      Replay.Common.TestFailure "Timestamp is populated in close event" "timestamp is empty"

testTimestampHasISOFormat :: Effect.Effect Replay.Common.TestResult
testTimestampHasISOFormat = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  let hasISOFormat = Data.String.contains (Data.String.Pattern "T") env.timestamp && Data.String.contains (Data.String.Pattern "Z") env.timestamp
  pure $
    if hasISOFormat then
      Replay.Common.TestSuccess "Timestamp has ISO format"
    else
      Replay.Common.TestFailure "Timestamp has ISO format" ("Timestamp does not appear to be ISO format: " <> env.timestamp)

testOpenEventPayloadIsCommandOpen :: Effect.Effect Replay.Common.TestResult
testOpenEventPayloadIsCommandOpen = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  let
    isCommandOpen = case env.payload of
      Replay.Protocol.Types.CommandOpen _ -> true
      _ -> false
  pure $
    if isCommandOpen then
      Replay.Common.TestSuccess "Open event payload is CommandOpen with request"
    else
      Replay.Common.TestFailure "Open event payload is CommandOpen with request" "payload is not CommandOpen"

testCloseEventPayloadIsEventClose :: Effect.Effect Replay.Common.TestResult
testCloseEventPayloadIsEventClose = do
  ctx <- Replay.TraceContext.newTrace
  let streamId = Replay.TraceContext.currentStreamId ctx
  closeEvent <- Replay.Stream.createCloseEvent ctx streamId Replay.Protocol.Types.ProgramChannel sampleBamlResponse
  let env = unwrapEnvelope closeEvent
  let
    isEventClose = case env.payload of
      Replay.Protocol.Types.EventClose _ -> true
      _ -> false
  pure $
    if isEventClose then
      Replay.Common.TestSuccess "Close event payload is EventClose with response"
    else
      Replay.Common.TestFailure "Close event payload is EventClose with response" "payload is not EventClose"

testOpenEventRequestPayloadMatchesInput :: Effect.Effect Replay.Common.TestResult
testOpenEventRequestPayloadMatchesInput = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  let
    matchesInput = case env.payload of
      Replay.Protocol.Types.CommandOpen req ->
        req.service == sampleBamlRequest.service &&
          Data.Argonaut.Core.stringify req.payload == Data.Argonaut.Core.stringify sampleBamlRequest.payload
      _ -> false
  pure $
    if matchesInput then
      Replay.Common.TestSuccess "Open event request payload matches input"
    else
      Replay.Common.TestFailure "Open event request payload matches input" "request payload does not match input"

testCloseEventResponsePayloadMatchesInput :: Effect.Effect Replay.Common.TestResult
testCloseEventResponsePayloadMatchesInput = do
  ctx <- Replay.TraceContext.newTrace
  let streamId = Replay.TraceContext.currentStreamId ctx
  closeEvent <- Replay.Stream.createCloseEvent ctx streamId Replay.Protocol.Types.ProgramChannel sampleBamlResponse
  let env = unwrapEnvelope closeEvent
  let
    matchesInput = case env.payload of
      Replay.Protocol.Types.EventClose resp ->
        resp.service == sampleBamlResponse.service &&
          Data.Argonaut.Core.stringify resp.payload == Data.Argonaut.Core.stringify sampleBamlResponse.payload
      _ -> false
  pure $
    if matchesInput then
      Replay.Common.TestSuccess "Close event response payload matches input"
    else
      Replay.Common.TestFailure "Close event response payload matches input" "response payload does not match input"

testRootContextHasNullParentStreamId :: Effect.Effect Replay.Common.TestResult
testRootContextHasNullParentStreamId = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  let actualParentId = Json.Nullable.jsonNullableToMaybe env.parentStreamId
  pure $
    if Data.Maybe.isNothing actualParentId then
      Replay.Common.TestSuccess "Root context has null parentStreamId in open event"
    else
      Replay.Common.TestFailure "Root context has null parentStreamId in open event" "parentStreamId should be null for root context"

testRootContextHasNullCausationStreamId :: Effect.Effect Replay.Common.TestResult
testRootContextHasNullCausationStreamId = do
  ctx <- Replay.TraceContext.newTrace
  openEvent <- Replay.Stream.createOpenEvent ctx Replay.Protocol.Types.ProgramChannel sampleBamlRequest
  let env = unwrapEnvelope openEvent
  let actualCausationId = Json.Nullable.jsonNullableToMaybe env.causationStreamId
  pure $
    if Data.Maybe.isNothing actualCausationId then
      Replay.Common.TestSuccess "Root context has null causationStreamId in open event"
    else
      Replay.Common.TestFailure "Root context has null causationStreamId in open event" "causationStreamId should be null for root context"

testOpenEventSeqConstantIsZero :: Effect.Effect Replay.Common.TestResult
testOpenEventSeqConstantIsZero = do
  pure $
    if Replay.Stream.openEventSeq == Replay.Protocol.Types.EventSeq 0 then
      Replay.Common.TestSuccess "openEventSeq constant is 0"
    else
      Replay.Common.TestFailure "openEventSeq constant is 0" "openEventSeq is not EventSeq 0"

testCloseEventSeqConstantIsOne :: Effect.Effect Replay.Common.TestResult
testCloseEventSeqConstantIsOne = do
  pure $
    if Replay.Stream.closeEventSeq == Replay.Protocol.Types.EventSeq 1 then
      Replay.Common.TestSuccess "closeEventSeq constant is 1"
    else
      Replay.Common.TestFailure "closeEventSeq constant is 1" "closeEventSeq is not EventSeq 1"

effectTests :: Effect.Effect (Array Replay.Common.TestResult)
effectTests = do
  r1 <- testCreateOpenEventHasEventSeqZero
  r2 <- testCreateCloseEventHasEventSeqOne
  r3 <- testOpenAndCloseEventsHaveMatchingStreamId
  r4 <- testTraceIdPropagatedToOpenEvent
  r5 <- testTraceIdPropagatedToCloseEvent
  r6 <- testCurrentStreamIdUsedForOpenEvent
  r7 <- testSiblingIndexPropagatedToOpenEvent
  r8 <- testSiblingIndexPropagatedToCloseEvent
  r9 <- testParentStreamIdPropagatedToOpenEvent
  r10 <- testCausationStreamIdPropagatedToOpenEvent
  r11 <- testTimestampPopulatedInOpenEvent
  r12 <- testTimestampPopulatedInCloseEvent
  r13 <- testTimestampHasISOFormat
  r14 <- testOpenEventPayloadIsCommandOpen
  r15 <- testCloseEventPayloadIsEventClose
  r16 <- testOpenEventRequestPayloadMatchesInput
  r17 <- testCloseEventResponsePayloadMatchesInput
  r18 <- testRootContextHasNullParentStreamId
  r19 <- testRootContextHasNullCausationStreamId
  r20 <- testOpenEventSeqConstantIsZero
  r21 <- testCloseEventSeqConstantIsOne
  pure [ r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21 ]

runTests :: Effect.Effect Replay.Common.TestResults
runTests = Replay.Common.computeResults <$> effectTests
