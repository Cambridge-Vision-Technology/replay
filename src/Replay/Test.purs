module Replay.Test
  ( runTests
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Maybe as Data.Maybe
import Data.String as Data.String
import Data.Tuple as Data.Tuple
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Foreign.Object as Foreign.Object
import Json.Nullable as Json.Nullable
import Replay.Client as Replay.Client
import Replay.Common as Replay.Common
import Replay.Handler as Replay.Handler
import Replay.Interceptor as Replay.Interceptor
import Replay.Recorder as Replay.Recorder
import Replay.Server as Replay.Server
import Replay.Types as Replay.Types
import Replay.Hash as Replay.Hash
import Replay.Recording as Replay.Recording
import Replay.Protocol.Types as Replay.Protocol.Types
import Replay.IdTranslation.Test as Replay.IdTranslation.Test
import Replay.Player as Replay.Player
import Replay.Player.Test as Replay.Player.Test

-- | Helper to create JSON object
makeObject :: Array (Data.Tuple.Tuple String Data.Argonaut.Core.Json) -> Data.Argonaut.Core.Json
makeObject pairs = Data.Argonaut.Core.fromObject (Foreign.Object.fromFoldable pairs)

testPort :: Int
testPort = 9876

testServerStartsAndStops :: Effect.Aff.Aff Replay.Common.TestResult
testServerStartsAndStops = do
  serverResult <- Replay.Server.startServer testPort (\_ -> pure unit)
  case serverResult of
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "server starts and stops" (show err)
    Data.Either.Right server -> do
      Effect.Aff.delay (Effect.Aff.Milliseconds 100.0)
      Replay.Server.stopServer server
      pure $ Replay.Common.TestSuccess "server starts and stops"

testClientConnects :: Effect.Aff.Aff Replay.Common.TestResult
testClientConnects = do
  serverResult <- Replay.Server.startServer (testPort + 1) (\_ -> pure unit)
  case serverResult of
    Data.Either.Left err -> do
      pure $ Replay.Common.TestFailure "client connects to server" ("Server failed to start: " <> show err)
    Data.Either.Right server -> do
      Effect.Aff.delay (Effect.Aff.Milliseconds 100.0)
      clientResult <- Replay.Client.connect ("ws://localhost:" <> show (testPort + 1))
      result <- case clientResult of
        Data.Either.Left err -> do
          pure $ Replay.Common.TestFailure "client connects to server" ("Client failed to connect: " <> show err)
        Data.Either.Right conn -> do
          Replay.Client.disconnect conn
          pure $ Replay.Common.TestSuccess "client connects to server"
      Replay.Server.stopServer server
      pure result

testMessageSend :: Effect.Aff.Aff Replay.Common.TestResult
testMessageSend = do
  serverResult <- Replay.Server.startServer (testPort + 2) \conn -> do
    Replay.Server.onMessage conn \msg -> do
      let responseMsg = "Echo: " <> msg
      Replay.Server.sendMessage conn responseMsg
  case serverResult of
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "message send" ("Server failed to start: " <> show err)
    Data.Either.Right server -> do
      Effect.Aff.delay (Effect.Aff.Milliseconds 100.0)
      clientResult <- Replay.Client.connect ("ws://localhost:" <> show (testPort + 2))
      result <- case clientResult of
        Data.Either.Left err ->
          pure $ Replay.Common.TestFailure "message send" ("Client failed to connect: " <> show err)
        Data.Either.Right conn -> do
          Effect.Class.liftEffect $ Replay.Client.onMessage conn \_ -> pure unit
          Effect.Class.liftEffect $ Replay.Server.sendMessage conn "test"
          Effect.Aff.delay (Effect.Aff.Milliseconds 100.0)
          Replay.Client.disconnect conn
          pure $ Replay.Common.TestSuccess "message send"
      Replay.Server.stopServer server
      pure result

testHarnessModeEncoding :: Replay.Common.TestResult
testHarnessModeEncoding =
  let
    modes =
      [ Replay.Types.ModePassthrough
      , Replay.Types.ModeRecord
      , Replay.Types.ModePlayback
      ]
    encodedStrings = map (Data.Argonaut.Core.stringify <<< Data.Argonaut.Encode.encodeJson) modes
    expected = [ "\"passthrough\"", "\"record\"", "\"playback\"" ]
  in
    if encodedStrings == expected then
      Replay.Common.TestSuccess "HarnessMode encodes correctly"
    else
      Replay.Common.TestFailure "HarnessMode encodes correctly" ("Got: " <> show encodedStrings)

testHarnessModeRoundtrip :: Replay.Common.TestResult
testHarnessModeRoundtrip =
  let
    modes =
      [ Replay.Types.ModePassthrough
      , Replay.Types.ModeRecord
      , Replay.Types.ModePlayback
      ]
    roundtrip mode =
      let
        encoded = Data.Argonaut.Encode.encodeJson mode
        decoded = Data.Argonaut.Decode.decodeJson encoded
      in
        decoded == Data.Either.Right mode
    allPass = Data.Array.all roundtrip modes
  in
    if allPass then
      Replay.Common.TestSuccess "HarnessMode roundtrip"
    else
      Replay.Common.TestFailure "HarnessMode roundtrip" "One or more modes failed roundtrip"

testWebSocketErrorEncoding :: Replay.Common.TestResult
testWebSocketErrorEncoding =
  let
    errors =
      [ Replay.Types.ConnectionFailed "test error"
      , Replay.Types.MessageSendFailed "send error"
      , Replay.Types.ServerStartFailed "start error"
      , Replay.Types.ConnectionClosed
      ]
    allEncode = Data.Array.all (\e -> Data.String.length (Data.Argonaut.Core.stringify (Data.Argonaut.Encode.encodeJson e)) > 0) errors
  in
    if allEncode then
      Replay.Common.TestSuccess "WebSocketError encodes correctly"
    else
      Replay.Common.TestFailure "WebSocketError encodes correctly" "One or more errors failed to encode"

testWebSocketErrorRoundtrip :: Replay.Common.TestResult
testWebSocketErrorRoundtrip =
  let
    errors =
      [ Replay.Types.ConnectionFailed "test error"
      , Replay.Types.MessageSendFailed "send error"
      , Replay.Types.ServerStartFailed "start error"
      , Replay.Types.ConnectionClosed
      ]
    roundtrip err =
      let
        encoded = Data.Argonaut.Encode.encodeJson err
        decoded = Data.Argonaut.Decode.decodeJson encoded
      in
        decoded == Data.Either.Right err
    allPass = Data.Array.all roundtrip errors
  in
    if allPass then
      Replay.Common.TestSuccess "WebSocketError roundtrip"
    else
      Replay.Common.TestFailure "WebSocketError roundtrip" "One or more errors failed roundtrip"

testEnvelopeWithCommand :: Replay.Common.TestResult
testEnvelopeWithCommand =
  let
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2024-01-01T00:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandClose
      }
    encoded = Data.Argonaut.Encode.encodeJson envelope
    str = Data.Argonaut.Core.stringify encoded
  in
    if Data.String.length str > 0 then
      Replay.Common.TestSuccess "Envelope with Command encodes correctly"
    else
      Replay.Common.TestFailure "Envelope with Command encodes correctly" "Empty encoded string"

testEnvelopeWithEvent :: Replay.Common.TestResult
testEnvelopeWithEvent =
  let
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2024-01-01T00:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.EventClose
          { service: "http"
          , payload: makeObject
              [ Data.Tuple.Tuple "statusCode" (Data.Argonaut.Core.fromNumber 200.0)
              , Data.Tuple.Tuple "body" (Data.Argonaut.Core.fromString "OK")
              ]
          }
      }
    encoded = Data.Argonaut.Encode.encodeJson envelope

    decoded :: Data.Either.Either Data.Argonaut.Decode.JsonDecodeError (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event)
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right _ ->
        Replay.Common.TestSuccess "Envelope with Event roundtrip"
      Data.Either.Left err ->
        Replay.Common.TestFailure "Envelope with Event roundtrip" (Data.Argonaut.Decode.printJsonDecodeError err)

testRecorderAccumulatesMessages :: Effect.Aff.Aff Replay.Common.TestResult
testRecorderAccumulatesMessages = do
  recorder <- Effect.Class.liftEffect $ Replay.Recorder.createRecorder "test-scenario"

  let message1 = createTestRecordedMessage "stream1" Replay.Recording.ToHarness
  let message2 = createTestRecordedMessage "stream2" Replay.Recording.FromHarness

  Effect.Class.liftEffect $ Replay.Recorder.recordMessage recorder message1
  Effect.Class.liftEffect $ Replay.Recorder.recordMessage recorder message2

  messages <- Effect.Class.liftEffect $ Replay.Recorder.getMessages recorder

  if Data.Array.length messages == 2 then
    pure $ Replay.Common.TestSuccess "Recorder accumulates messages"
  else
    pure $ Replay.Common.TestFailure "Recorder accumulates messages" ("Expected 2 messages, got " <> show (Data.Array.length messages))

testRecorderGetScenarioName :: Effect.Aff.Aff Replay.Common.TestResult
testRecorderGetScenarioName = do
  recorder <- Effect.Class.liftEffect $ Replay.Recorder.createRecorder "my-scenario"
  let scenarioName = Replay.Recorder.getScenarioName recorder
  if scenarioName == "my-scenario" then
    pure $ Replay.Common.TestSuccess "Recorder getScenarioName"
  else
    pure $ Replay.Common.TestFailure "Recorder getScenarioName" ("Expected 'my-scenario', got " <> scenarioName)

testHandlerPassthroughMode :: Effect.Aff.Aff Replay.Common.TestResult
testHandlerPassthroughMode = do
  pendingForwards <- Effect.Class.liftEffect Replay.Handler.emptyPendingForwards
  interceptRegistry <- Effect.Class.liftEffect Replay.Interceptor.newRegistry
  let commandEnvelope = createTestCommandEnvelope "test-stream"
  result <- Replay.Handler.handleCommand
    Replay.Types.ModePassthrough
    Data.Maybe.Nothing
    Data.Maybe.Nothing
    pendingForwards
    interceptRegistry
    commandEnvelope
  case result of
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "Handler passthrough mode" ("Unexpected error: " <> show err)
    Data.Either.Right handleResult ->
      case handleResult of
        Replay.Handler.ForwardToPlatform _ ->
          pure $ Replay.Common.TestSuccess "Handler passthrough mode returns ForwardToPlatform"
        Replay.Handler.RespondDirectly _ ->
          pure $ Replay.Common.TestFailure "Handler passthrough mode" "Expected ForwardToPlatform, got RespondDirectly"
        Replay.Handler.ForwardToProgram _ ->
          pure $ Replay.Common.TestFailure "Handler passthrough mode" "Expected ForwardToPlatform, got ForwardToProgram"
        Replay.Handler.NoResponse ->
          pure $ Replay.Common.TestFailure "Handler passthrough mode" "Expected ForwardToPlatform, got NoResponse"

testHandlerRecordMode :: Effect.Aff.Aff Replay.Common.TestResult
testHandlerRecordMode = do
  pendingForwards <- Effect.Class.liftEffect Replay.Handler.emptyPendingForwards
  interceptRegistry <- Effect.Class.liftEffect Replay.Interceptor.newRegistry
  recorder <- Effect.Class.liftEffect $ Replay.Recorder.createRecorder "test-scenario"
  let commandEnvelope = createTestCommandEnvelope "test-stream"
  result <- Replay.Handler.handleCommand
    Replay.Types.ModeRecord
    (Data.Maybe.Just recorder)
    Data.Maybe.Nothing
    pendingForwards
    interceptRegistry
    commandEnvelope
  case result of
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "Handler record mode" ("Unexpected error: " <> show err)
    Data.Either.Right handleResult ->
      case handleResult of
        Replay.Handler.ForwardToPlatform _ -> do
          messages <- Effect.Class.liftEffect $ Replay.Recorder.getMessages recorder
          if Data.Array.length messages == 1 then
            pure $ Replay.Common.TestSuccess "Handler record mode records command and forwards to platform"
          else
            pure $ Replay.Common.TestFailure "Handler record mode" ("Expected 1 message (command), got " <> show (Data.Array.length messages))
        _ ->
          pure $ Replay.Common.TestFailure "Handler record mode" ("Expected ForwardToPlatform, got " <> show handleResult)

testHandlerPlaybackModeWithoutPlayer :: Effect.Aff.Aff Replay.Common.TestResult
testHandlerPlaybackModeWithoutPlayer = do
  pendingForwards <- Effect.Class.liftEffect Replay.Handler.emptyPendingForwards
  interceptRegistry <- Effect.Class.liftEffect Replay.Interceptor.newRegistry
  let commandEnvelope = createTestCommandEnvelope "test-stream"
  result <- Replay.Handler.handleCommand
    Replay.Types.ModePlayback
    Data.Maybe.Nothing
    Data.Maybe.Nothing
    pendingForwards
    interceptRegistry
    commandEnvelope
  case result of
    Data.Either.Left (Replay.Handler.UnexpectedCommand _) ->
      pure $ Replay.Common.TestSuccess "Handler playback mode without player returns error"
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "Handler playback mode without player" ("Unexpected error type: " <> show err)
    Data.Either.Right _ ->
      pure $ Replay.Common.TestFailure "Handler playback mode without player" "Expected error, got success"

testHandlerPlaybackModeWithPlayer :: Effect.Aff.Aff Replay.Common.TestResult
testHandlerPlaybackModeWithPlayer = do
  pendingForwards <- Effect.Class.liftEffect Replay.Handler.emptyPendingForwards
  interceptRegistry <- Effect.Class.liftEffect Replay.Interceptor.newRegistry
  let
    httpRequest :: Replay.Protocol.Types.RequestPayload
    httpRequest =
      { service: "http"
      , payload: makeObject
          [ Data.Tuple.Tuple "method" (Data.Argonaut.Core.fromString "GET")
          , Data.Tuple.Tuple "url" (Data.Argonaut.Core.fromString "https://example.com/test")
          , Data.Tuple.Tuple "body" Data.Argonaut.Core.jsonNull
          , Data.Tuple.Tuple "headers" (Data.Argonaut.Core.fromArray [])
          ]
      }
  Replay.Hash.PayloadHash commandHash <- Effect.Class.liftEffect $ Replay.Hash.computePayloadHash httpRequest
  let
    httpResponse :: Replay.Protocol.Types.ResponsePayload
    httpResponse =
      { service: "http"
      , payload: makeObject
          [ Data.Tuple.Tuple "statusCode" (Data.Argonaut.Core.fromNumber 200.0)
          , Data.Tuple.Tuple "body" (Data.Argonaut.Core.fromString "OK")
          ]
      }
    commandMessage =
      { envelope: Replay.Protocol.Types.Envelope
          { streamId: Replay.Protocol.Types.StreamId "recorded-stream"
          , traceId: Replay.Protocol.Types.TraceId "recorded-trace"
          , causationStreamId: Json.Nullable.jsonNull
          , parentStreamId: Json.Nullable.jsonNull
          , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
          , eventSeq: Replay.Protocol.Types.EventSeq 0
          , timestamp: "2024-01-01T00:00:00.000Z"
          , channel: Replay.Protocol.Types.ProgramChannel
          , payloadHash: Data.Maybe.Nothing
          , payload: Replay.Recording.PayloadCommand (Replay.Protocol.Types.CommandOpen httpRequest)
          }
      , recordedAt: "2024-01-01T00:00:00.000Z"
      , direction: Replay.Recording.ToHarness
      , hash: Data.Maybe.Just commandHash
      }
    responseMessage =
      { envelope: Replay.Protocol.Types.Envelope
          { streamId: Replay.Protocol.Types.StreamId "recorded-stream"
          , traceId: Replay.Protocol.Types.TraceId "recorded-trace"
          , causationStreamId: Json.Nullable.jsonNull
          , parentStreamId: Json.Nullable.jsonNull
          , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
          , eventSeq: Replay.Protocol.Types.EventSeq 1
          , timestamp: "2024-01-01T00:00:01.000Z"
          , channel: Replay.Protocol.Types.ProgramChannel
          , payloadHash: Data.Maybe.Nothing
          , payload: Replay.Recording.PayloadEvent (Replay.Protocol.Types.EventClose httpResponse)
          }
      , recordedAt: "2024-01-01T00:00:01.000Z"
      , direction: Replay.Recording.FromHarness
      , hash: Data.Maybe.Nothing
      }
    recording =
      { schemaVersion: Replay.Recording.currentSchemaVersion
      , scenarioName: "test-scenario"
      , recordedAt: "2024-01-01T00:00:00.000Z"
      , messages: [ commandMessage, responseMessage ]
      }
  player <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording
  let
    playbackCommandEnvelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "playback-stream"
      , traceId: Replay.Protocol.Types.TraceId "playback-trace"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2024-02-01T00:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandOpen httpRequest
      }
  result <- Replay.Handler.handleCommand
    Replay.Types.ModePlayback
    Data.Maybe.Nothing
    (Data.Maybe.Just player)
    pendingForwards
    interceptRegistry
    playbackCommandEnvelope
  case result of
    Data.Either.Right handleResult ->
      case handleResult of
        Replay.Handler.RespondDirectly (Replay.Protocol.Types.Envelope eventEnv) ->
          case eventEnv.payload of
            Replay.Protocol.Types.EventClose resp ->
              if resp.service == "http" then
                let
                  maybeStatusCode = do
                    obj <- Data.Argonaut.Core.toObject resp.payload
                    statusVal <- Foreign.Object.lookup "statusCode" obj
                    Data.Argonaut.Core.toNumber statusVal
                  maybeBody = do
                    obj <- Data.Argonaut.Core.toObject resp.payload
                    bodyVal <- Foreign.Object.lookup "body" obj
                    Data.Argonaut.Core.toString bodyVal
                in
                  case Data.Tuple.Tuple maybeStatusCode maybeBody of
                    Data.Tuple.Tuple (Data.Maybe.Just 200.0) (Data.Maybe.Just "OK") ->
                      pure $ Replay.Common.TestSuccess "Handler playback mode returns recorded response"
                    _ ->
                      pure $ Replay.Common.TestFailure "Handler playback mode" ("Wrong response: " <> Data.Argonaut.Core.stringify resp.payload)
              else
                pure $ Replay.Common.TestFailure "Handler playback mode" ("Expected http service, got " <> resp.service)
            _ ->
              pure $ Replay.Common.TestFailure "Handler playback mode" "Expected EventClose"
        _ ->
          pure $ Replay.Common.TestFailure "Handler playback mode" ("Expected RespondDirectly, got " <> show handleResult)
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "Handler playback mode" ("Unexpected error: " <> show err)

createTestRecordedMessage :: String -> Replay.Recording.MessageDirection -> Replay.Recording.RecordedMessage
createTestRecordedMessage streamIdStr direction =
  { envelope: Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId streamIdStr
      , traceId: Replay.Protocol.Types.TraceId "trace1"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2024-01-01T00:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Recording.PayloadCommand Replay.Protocol.Types.CommandClose
      }
  , recordedAt: "2024-01-01T00:00:00.000Z"
  , direction
  , hash: Data.Maybe.Nothing
  }

createTestCommandEnvelope :: String -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
createTestCommandEnvelope streamIdStr =
  let
    httpRequest :: Replay.Protocol.Types.RequestPayload
    httpRequest =
      { service: "http"
      , payload: makeObject
          [ Data.Tuple.Tuple "method" (Data.Argonaut.Core.fromString "GET")
          , Data.Tuple.Tuple "url" (Data.Argonaut.Core.fromString "https://example.com/test")
          , Data.Tuple.Tuple "body" Data.Argonaut.Core.jsonNull
          , Data.Tuple.Tuple "headers" (Data.Argonaut.Core.fromArray [])
          ]
      }
  in
    Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId streamIdStr
      , traceId: Replay.Protocol.Types.TraceId "trace1"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2024-01-01T00:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandOpen httpRequest
      }

idTranslationTests :: Array Replay.Common.TestResult
idTranslationTests = Replay.IdTranslation.Test.runTests.results

playerTests :: Effect.Aff.Aff (Array Replay.Common.TestResult)
playerTests = _.results <$> Replay.Player.Test.runTests

pureTests :: Array Replay.Common.TestResult
pureTests =
  [ testHarnessModeEncoding
  , testHarnessModeRoundtrip
  , testWebSocketErrorEncoding
  , testWebSocketErrorRoundtrip
  , testEnvelopeWithCommand
  , testEnvelopeWithEvent
  ] <> idTranslationTests

effectTests :: Effect.Aff.Aff (Array Replay.Common.TestResult)
effectTests = do
  r1 <- testServerStartsAndStops
  Effect.Aff.delay (Effect.Aff.Milliseconds 200.0)
  r2 <- testClientConnects
  Effect.Aff.delay (Effect.Aff.Milliseconds 200.0)
  r3 <- testMessageSend
  pure [ r1, r2, r3 ]

recorderHandlerTests :: Effect.Aff.Aff (Array Replay.Common.TestResult)
recorderHandlerTests = do
  r1 <- testRecorderAccumulatesMessages
  r2 <- testRecorderGetScenarioName
  r3 <- testHandlerPassthroughMode
  r4 <- testHandlerRecordMode
  r5 <- testHandlerPlaybackModeWithoutPlayer
  r6 <- testHandlerPlaybackModeWithPlayer
  pure [ r1, r2, r3, r4, r5, r6 ]

runTests :: Effect.Aff.Aff Replay.Common.TestResults
runTests = do
  effectResults <- effectTests
  newModuleResults <- recorderHandlerTests
  playerTestResults <- playerTests
  let allResults = pureTests <> effectResults <> newModuleResults <> playerTestResults
  pure $ Replay.Common.computeResults allResults
