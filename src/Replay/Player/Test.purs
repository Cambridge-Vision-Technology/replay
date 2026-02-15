module Replay.Player.Test
  ( runTests
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Either as Data.Either
import Data.Int as Data.Int
import Data.Maybe as Data.Maybe
import Data.Tuple as Data.Tuple
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Foreign.Object as Foreign.Object
import Json.Nullable as Json.Nullable
import Replay.Common as Replay.Common
import Replay.IdTranslation as Replay.IdTranslation
import Replay.Player as Replay.Player
import Replay.Hash as Replay.Hash
import Replay.Recording as Replay.Recording
import Replay.Protocol.Types as Replay.Protocol.Types

makeTestEnvelope
  :: forall a
   . String
  -> String
  -> a
  -> Replay.Protocol.Types.Envelope a
makeTestEnvelope streamId traceId payload =
  Replay.Protocol.Types.Envelope
    { streamId: Replay.Protocol.Types.StreamId streamId
    , traceId: Replay.Protocol.Types.TraceId traceId
    , causationStreamId: Json.Nullable.jsonNull
    , parentStreamId: Json.Nullable.jsonNull
    , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
    , eventSeq: Replay.Protocol.Types.EventSeq 0
    , timestamp: "2025-01-08T12:00:00.000Z"
    , channel: Replay.Protocol.Types.ProgramChannel
    , payloadHash: Data.Maybe.Nothing
    , payload
    }

-- | Helper to create JSON object
makeObject :: Array (Data.Tuple.Tuple String Data.Argonaut.Core.Json) -> Data.Argonaut.Core.Json
makeObject pairs = Data.Argonaut.Core.fromObject (Foreign.Object.fromFoldable pairs)

makeHttpRequest :: String -> String -> Replay.Protocol.Types.RequestPayload
makeHttpRequest method url =
  { service: "http"
  , payload: makeObject
      [ Data.Tuple.Tuple "method" (Data.Argonaut.Core.fromString method)
      , Data.Tuple.Tuple "url" (Data.Argonaut.Core.fromString url)
      , Data.Tuple.Tuple "headers" (Data.Argonaut.Core.fromArray [])
      ]
  }

makeHttpResponse :: Int -> String -> Replay.Protocol.Types.ResponsePayload
makeHttpResponse statusCode body =
  { service: "http"
  , payload: makeObject
      [ Data.Tuple.Tuple "statusCode" (Data.Argonaut.Core.fromNumber (Data.Int.toNumber statusCode))
      , Data.Tuple.Tuple "body" (Data.Argonaut.Core.fromString body)
      ]
  }

makeFileDownloadRequest :: String -> Replay.Protocol.Types.RequestPayload
makeFileDownloadRequest url =
  { service: "file_download"
  , payload: makeObject
      [ Data.Tuple.Tuple "url" (Data.Argonaut.Core.fromString url)
      ]
  }

makeFileDownloadResponse :: String -> Replay.Protocol.Types.ResponsePayload
makeFileDownloadResponse contentBase64 =
  { service: "file_download"
  , payload: makeObject
      [ Data.Tuple.Tuple "contentBase64" (Data.Argonaut.Core.fromString contentBase64)
      ]
  }

makeCommandMessage
  :: String
  -> String
  -> Replay.Protocol.Types.RequestPayload
  -> String
  -> Replay.Recording.RecordedMessage
makeCommandMessage streamId traceId requestPayload hashValue =
  { envelope: makeTestEnvelope streamId traceId
      (Replay.Recording.PayloadCommand (Replay.Protocol.Types.CommandOpen requestPayload))
  , recordedAt: "2025-01-08T12:00:00.000Z"
  , direction: Replay.Recording.ToHarness
  , hash: Data.Maybe.Just hashValue
  }

makeCommandMessageEffect
  :: String
  -> String
  -> Replay.Protocol.Types.RequestPayload
  -> Effect.Effect Replay.Recording.RecordedMessage
makeCommandMessageEffect streamId traceId requestPayload = do
  Replay.Hash.PayloadHash hashValue <- Replay.Hash.computePayloadHash requestPayload
  pure $ makeCommandMessage streamId traceId requestPayload hashValue

makeResponseMessage
  :: String
  -> String
  -> Replay.Protocol.Types.ResponsePayload
  -> Replay.Recording.RecordedMessage
makeResponseMessage streamId traceId responsePayload =
  { envelope: makeTestEnvelope streamId traceId
      (Replay.Recording.PayloadEvent (Replay.Protocol.Types.EventClose responsePayload))
  , recordedAt: "2025-01-08T12:00:01.000Z"
  , direction: Replay.Recording.FromHarness
  , hash: Data.Maybe.Nothing
  }

makeTestRecording :: Array Replay.Recording.RecordedMessage -> Replay.Recording.Recording
makeTestRecording messages =
  { schemaVersion: Replay.Recording.currentSchemaVersion
  , scenarioName: "test-scenario"
  , recordedAt: "2025-01-08T12:00:00.000Z"
  , messages
  }

testFindMatchReturnsCorrectMessage :: Effect.Aff.Aff Replay.Common.TestResult
testFindMatchReturnsCorrectMessage = do
  let
    request1 = makeHttpRequest "GET" "https://example.com/api/1"
    request2 = makeHttpRequest "GET" "https://example.com/api/2"

  messages <- Effect.Class.liftEffect do
    cmd1 <- makeCommandMessageEffect "stream1" "trace1" request1
    cmd2 <- makeCommandMessageEffect "stream2" "trace1" request2
    pure
      [ cmd1
      , makeResponseMessage "stream1" "trace1" (makeHttpResponse 200 "response1")
      , cmd2
      , makeResponseMessage "stream2" "trace1" (makeHttpResponse 200 "response2")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  result <- Effect.Class.liftEffect $ Replay.Player.findMatch request2 state

  case result of
    Data.Maybe.Just (Data.Tuple.Tuple index msg) ->
      if index == 2 then
        pure $ Replay.Common.TestSuccess "findMatch returns correct matching message"
      else
        pure $ Replay.Common.TestFailure "findMatch returns correct matching message" ("Expected index 2, got " <> show index)
    Data.Maybe.Nothing ->
      pure $ Replay.Common.TestFailure "findMatch returns correct matching message" "Expected Just, got Nothing"

testFindMatchRespectsUsedMessages :: Effect.Aff.Aff Replay.Common.TestResult
testFindMatchRespectsUsedMessages = do
  let request = makeHttpRequest "GET" "https://example.com/api"

  messages <- Effect.Class.liftEffect do
    cmd1 <- makeCommandMessageEffect "stream1" "trace1" request
    cmd2 <- makeCommandMessageEffect "stream2" "trace1" request
    pure
      [ cmd1
      , makeResponseMessage "stream1" "trace1" (makeHttpResponse 200 "response1")
      , cmd2
      , makeResponseMessage "stream2" "trace1" (makeHttpResponse 200 "response2")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  Effect.Class.liftEffect $ Replay.Player.markMessageUsed state 0

  result <- Effect.Class.liftEffect $ Replay.Player.findMatch request state

  case result of
    Data.Maybe.Just (Data.Tuple.Tuple index _) ->
      if index == 2 then
        pure $ Replay.Common.TestSuccess "findMatch respects already-used messages"
      else
        pure $ Replay.Common.TestFailure "findMatch respects already-used messages" ("Expected index 2, got " <> show index)
    Data.Maybe.Nothing ->
      pure $ Replay.Common.TestFailure "findMatch respects already-used messages" "Expected Just, got Nothing"

testFindMatchReturnsNothingWhenNoMatch :: Effect.Aff.Aff Replay.Common.TestResult
testFindMatchReturnsNothingWhenNoMatch = do
  let
    recordedRequest = makeHttpRequest "GET" "https://example.com/api/1"
    searchRequest = makeHttpRequest "GET" "https://example.com/api/different"

  messages <- Effect.Class.liftEffect do
    cmd <- makeCommandMessageEffect "stream1" "trace1" recordedRequest
    pure
      [ cmd
      , makeResponseMessage "stream1" "trace1" (makeHttpResponse 200 "response1")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  result <- Effect.Class.liftEffect $ Replay.Player.findMatch searchRequest state

  case result of
    Data.Maybe.Nothing ->
      pure $ Replay.Common.TestSuccess "findMatch returns Nothing when no matching request exists"
    Data.Maybe.Just _ ->
      pure $ Replay.Common.TestFailure "findMatch returns Nothing when no matching request exists" "Expected Nothing, got Just"

testSameRequestCanOnlyMatchOnce :: Effect.Aff.Aff Replay.Common.TestResult
testSameRequestCanOnlyMatchOnce = do
  let request = makeHttpRequest "GET" "https://example.com/api"

  messages <- Effect.Class.liftEffect do
    cmd <- makeCommandMessageEffect "stream1" "trace1" request
    pure
      [ cmd
      , makeResponseMessage "stream1" "trace1" (makeHttpResponse 200 "response1")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  result1 <- Effect.Class.liftEffect $ Replay.Player.findMatch request state
  case result1 of
    Data.Maybe.Just (Data.Tuple.Tuple index _) ->
      Effect.Class.liftEffect $ Replay.Player.markMessageUsed state index
    Data.Maybe.Nothing ->
      pure unit

  result2 <- Effect.Class.liftEffect $ Replay.Player.findMatch request state

  case result2 of
    Data.Maybe.Nothing ->
      pure $ Replay.Common.TestSuccess "Same request can only be matched once"
    Data.Maybe.Just _ ->
      pure $ Replay.Common.TestFailure "Same request can only be matched once" "Second match should return Nothing"

testPlaybackRequestTranslatesIdsCorrectly :: Effect.Aff.Aff Replay.Common.TestResult
testPlaybackRequestTranslatesIdsCorrectly = do
  let
    request = makeHttpRequest "GET" "https://example.com/api"
    recordedStreamId = "recorded-stream-123"
    recordedTraceId = "recorded-trace-456"

  messages <- Effect.Class.liftEffect do
    cmd <- makeCommandMessageEffect recordedStreamId recordedTraceId request
    pure
      [ cmd
      , makeResponseMessage recordedStreamId recordedTraceId (makeHttpResponse 200 "OK")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  let
    playbackStreamId = "playback-stream-789"
    playbackTraceId = "playback-trace-012"
    commandEnvelope = makeTestEnvelope playbackStreamId playbackTraceId
      (Replay.Protocol.Types.CommandOpen request)

  result <- Replay.Player.playbackRequest commandEnvelope state

  case result of
    Data.Either.Right (Replay.Protocol.Types.Envelope eventEnv) ->
      if
        eventEnv.streamId == Replay.Protocol.Types.StreamId playbackStreamId
          && eventEnv.traceId == Replay.Protocol.Types.TraceId playbackTraceId then
        pure $ Replay.Common.TestSuccess "playbackRequest translates IDs correctly"
      else
        pure $ Replay.Common.TestFailure "playbackRequest translates IDs correctly"
          ( "Response has wrong IDs. StreamId: " <> show eventEnv.streamId
              <> ", TraceId: "
              <> show eventEnv.traceId
          )
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "playbackRequest translates IDs correctly" ("Got error: " <> show err)

testPlaybackRequestReturnsNoMatchFound :: Effect.Aff.Aff Replay.Common.TestResult
testPlaybackRequestReturnsNoMatchFound = do
  let
    recordedRequest = makeHttpRequest "GET" "https://example.com/api/1"
    playbackRequest' = makeHttpRequest "GET" "https://example.com/api/different"

  messages <- Effect.Class.liftEffect do
    cmd <- makeCommandMessageEffect "stream1" "trace1" recordedRequest
    pure
      [ cmd
      , makeResponseMessage "stream1" "trace1" (makeHttpResponse 200 "response1")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  let
    commandEnvelope = makeTestEnvelope "playback-stream" "playback-trace"
      (Replay.Protocol.Types.CommandOpen playbackRequest')

  result <- Replay.Player.playbackRequest commandEnvelope state

  case result of
    Data.Either.Left (Replay.Player.NoMatchFound _) ->
      pure $ Replay.Common.TestSuccess "playbackRequest returns NoMatchFound when no matching request exists"
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "playbackRequest returns NoMatchFound when no matching request exists"
        ("Got different error: " <> show err)
    Data.Either.Right _ ->
      pure $ Replay.Common.TestFailure "playbackRequest returns NoMatchFound when no matching request exists"
        "Expected Left NoMatchFound, got Right"

testPlaybackRequestRegistersIdMapping :: Effect.Aff.Aff Replay.Common.TestResult
testPlaybackRequestRegistersIdMapping = do
  let
    request = makeHttpRequest "GET" "https://example.com/api"
    recordedStreamId = "recorded-stream-id"
    recordedTraceId = "recorded-trace-id"

  messages <- Effect.Class.liftEffect do
    cmd <- makeCommandMessageEffect recordedStreamId recordedTraceId request
    pure
      [ cmd
      , makeResponseMessage recordedStreamId recordedTraceId (makeHttpResponse 200 "OK")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  let
    playbackStreamId = "playback-stream-id"
    playbackTraceId = "playback-trace-id"
    commandEnvelope = makeTestEnvelope playbackStreamId playbackTraceId
      (Replay.Protocol.Types.CommandOpen request)

  _ <- Replay.Player.playbackRequest commandEnvelope state

  translationMap <- Effect.Class.liftEffect $ Replay.Player.getTranslationMap state

  let
    streamIdLookup = Replay.IdTranslation.translateStreamIdToPlayback
      (Replay.Protocol.Types.StreamId recordedStreamId)
      translationMap
    traceIdLookup = Replay.IdTranslation.translateTraceIdToPlayback
      (Replay.Protocol.Types.TraceId recordedTraceId)
      translationMap

  case streamIdLookup, traceIdLookup of
    Data.Maybe.Just sid, Data.Maybe.Just tid ->
      if
        sid == Replay.Protocol.Types.StreamId playbackStreamId
          && tid == Replay.Protocol.Types.TraceId playbackTraceId then
        pure $ Replay.Common.TestSuccess "playbackRequest registers ID mapping"
      else
        pure $ Replay.Common.TestFailure "playbackRequest registers ID mapping"
          ("Got wrong mapped IDs: " <> show sid <> ", " <> show tid)
    _, _ ->
      pure $ Replay.Common.TestFailure "playbackRequest registers ID mapping" "ID mapping not found"

testPlaybackRequestMarksMessageAsUsed :: Effect.Aff.Aff Replay.Common.TestResult
testPlaybackRequestMarksMessageAsUsed = do
  let request = makeHttpRequest "GET" "https://example.com/api"

  messages <- Effect.Class.liftEffect do
    cmd <- makeCommandMessageEffect "stream1" "trace1" request
    pure
      [ cmd
      , makeResponseMessage "stream1" "trace1" (makeHttpResponse 200 "OK")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  let
    commandEnvelope = makeTestEnvelope "playback-stream" "playback-trace"
      (Replay.Protocol.Types.CommandOpen request)

  _ <- Replay.Player.playbackRequest commandEnvelope state

  result <- Effect.Class.liftEffect $ Replay.Player.findMatch request state

  case result of
    Data.Maybe.Nothing ->
      pure $ Replay.Common.TestSuccess "playbackRequest marks message as used"
    Data.Maybe.Just _ ->
      pure $ Replay.Common.TestFailure "playbackRequest marks message as used" "Message should be marked as used"

testPlaybackRequestReturnsCorrectResponsePayload :: Effect.Aff.Aff Replay.Common.TestResult
testPlaybackRequestReturnsCorrectResponsePayload = do
  let
    request = makeHttpRequest "GET" "https://example.com/api"
    expectedResponse = makeHttpResponse 200 "test-body"

  messages <- Effect.Class.liftEffect do
    cmd <- makeCommandMessageEffect "stream1" "trace1" request
    pure
      [ cmd
      , makeResponseMessage "stream1" "trace1" expectedResponse
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  let
    commandEnvelope = makeTestEnvelope "playback-stream" "playback-trace"
      (Replay.Protocol.Types.CommandOpen request)

  result <- Replay.Player.playbackRequest commandEnvelope state

  case result of
    Data.Either.Right (Replay.Protocol.Types.Envelope eventEnv) ->
      case eventEnv.payload of
        Replay.Protocol.Types.EventClose r ->
          if r.service == "http" then
            pure $ Replay.Common.TestSuccess "playbackRequest returns correct response payload"
          else
            pure $ Replay.Common.TestFailure "playbackRequest returns correct response payload"
              ("Got wrong service: " <> r.service)
        _ ->
          pure $ Replay.Common.TestFailure "playbackRequest returns correct response payload"
            "Expected EventClose"
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "playbackRequest returns correct response payload" ("Got error: " <> show err)

testFindMatchMatchesByServiceType :: Effect.Aff.Aff Replay.Common.TestResult
testFindMatchMatchesByServiceType = do
  let
    httpRequest = makeHttpRequest "GET" "https://example.com/api"
    fileDownloadRequest = makeFileDownloadRequest "https://example.com/file"

  messages <- Effect.Class.liftEffect do
    cmdHttp <- makeCommandMessageEffect "stream1" "trace1" httpRequest
    cmdFd <- makeCommandMessageEffect "stream2" "trace1" fileDownloadRequest
    pure
      [ cmdHttp
      , makeResponseMessage "stream1" "trace1" (makeHttpResponse 200 "response1")
      , cmdFd
      , makeResponseMessage "stream2" "trace1" (makeFileDownloadResponse "dGVzdA==")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  httpResult <- Effect.Class.liftEffect $ Replay.Player.findMatch httpRequest state
  fileDownloadResult <- Effect.Class.liftEffect $ Replay.Player.findMatch fileDownloadRequest state

  case httpResult, fileDownloadResult of
    Data.Maybe.Just (Data.Tuple.Tuple httpIdx _), Data.Maybe.Just (Data.Tuple.Tuple fdIdx _) ->
      if httpIdx == 0 && fdIdx == 2 then
        pure $ Replay.Common.TestSuccess "findMatch matches by service type correctly"
      else
        pure $ Replay.Common.TestFailure "findMatch matches by service type correctly"
          ("Expected indices 0 and 2, got " <> show httpIdx <> " and " <> show fdIdx)
    _, _ ->
      pure $ Replay.Common.TestFailure "findMatch matches by service type correctly" "Expected both to match"

testCreatePlayerStateInitializesCorrectly :: Effect.Aff.Aff Replay.Common.TestResult
testCreatePlayerStateInitializesCorrectly = do
  let recording = makeTestRecording []

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  translationMap <- Effect.Class.liftEffect $ Replay.Player.getTranslationMap state

  if
    state.recording.scenarioName == "test-scenario"
      && translationMap == Replay.IdTranslation.emptyTranslationMap then
    pure $ Replay.Common.TestSuccess "createPlayerState initializes state correctly"
  else
    pure $ Replay.Common.TestFailure "createPlayerState initializes state correctly" "State not initialized correctly"

-- | Verify that multiple messages with the same hash are returned in recording
-- | order (ascending index), not reverse order. This is critical for effects
-- | like clock requests where all payloads hash identically but each response
-- | carries a different timestamp.
testFindMatchReturnsSameHashInRecordingOrder :: Effect.Aff.Aff Replay.Common.TestResult
testFindMatchReturnsSameHashInRecordingOrder = do
  let request = makeHttpRequest "GET" "https://example.com/api"

  messages <- Effect.Class.liftEffect do
    cmd1 <- makeCommandMessageEffect "stream1" "trace1" request
    cmd2 <- makeCommandMessageEffect "stream2" "trace1" request
    cmd3 <- makeCommandMessageEffect "stream3" "trace1" request
    pure
      [ cmd1
      , makeResponseMessage "stream1" "trace1" (makeHttpResponse 200 "first")
      , cmd2
      , makeResponseMessage "stream2" "trace1" (makeHttpResponse 200 "second")
      , cmd3
      , makeResponseMessage "stream3" "trace1" (makeHttpResponse 200 "third")
      ]
  let recording = makeTestRecording messages

  state <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording

  result1 <- Effect.Class.liftEffect $ Replay.Player.findMatch request state
  case result1 of
    Data.Maybe.Just (Data.Tuple.Tuple idx1 _) -> do
      Effect.Class.liftEffect $ Replay.Player.markMessageUsed state idx1
      result2 <- Effect.Class.liftEffect $ Replay.Player.findMatch request state
      case result2 of
        Data.Maybe.Just (Data.Tuple.Tuple idx2 _) -> do
          Effect.Class.liftEffect $ Replay.Player.markMessageUsed state idx2
          result3 <- Effect.Class.liftEffect $ Replay.Player.findMatch request state
          case result3 of
            Data.Maybe.Just (Data.Tuple.Tuple idx3 _) ->
              if idx1 == 0 && idx2 == 2 && idx3 == 4 then
                pure $ Replay.Common.TestSuccess "findMatch returns same-hash messages in ascending recording order"
              else
                pure $ Replay.Common.TestFailure "findMatch returns same-hash messages in ascending recording order"
                  ("Expected indices [0, 2, 4], got [" <> show idx1 <> ", " <> show idx2 <> ", " <> show idx3 <> "]")
            Data.Maybe.Nothing ->
              pure $ Replay.Common.TestFailure "findMatch returns same-hash messages in ascending recording order" "Third match returned Nothing"
        Data.Maybe.Nothing ->
          pure $ Replay.Common.TestFailure "findMatch returns same-hash messages in ascending recording order" "Second match returned Nothing"
    Data.Maybe.Nothing ->
      pure $ Replay.Common.TestFailure "findMatch returns same-hash messages in ascending recording order" "First match returned Nothing"

allTests :: Effect.Aff.Aff (Array Replay.Common.TestResult)
allTests = do
  r1 <- testFindMatchReturnsCorrectMessage
  r2 <- testFindMatchRespectsUsedMessages
  r3 <- testFindMatchReturnsNothingWhenNoMatch
  r4 <- testSameRequestCanOnlyMatchOnce
  r5 <- testPlaybackRequestTranslatesIdsCorrectly
  r6 <- testPlaybackRequestReturnsNoMatchFound
  r7 <- testPlaybackRequestRegistersIdMapping
  r8 <- testPlaybackRequestMarksMessageAsUsed
  r9 <- testPlaybackRequestReturnsCorrectResponsePayload
  r10 <- testFindMatchMatchesByServiceType
  r11 <- testCreatePlayerStateInitializesCorrectly
  r12 <- testFindMatchReturnsSameHashInRecordingOrder
  pure [ r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 ]

runTests :: Effect.Aff.Aff Replay.Common.TestResults
runTests = Replay.Common.computeResults <$> allTests
