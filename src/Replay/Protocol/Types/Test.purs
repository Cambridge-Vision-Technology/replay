module Replay.Protocol.Types.Test
  ( runTests
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Either as Data.Either
import Data.Maybe as Data.Maybe
import Data.Tuple as Data.Tuple
import Foreign.Object as Foreign.Object
import Json.Nullable as Json.Nullable
import Replay.Common as Replay.Common
import Replay.Protocol.Types as Replay.Protocol.Types

roundtripTest
  :: forall a
   . Show a
  => Eq a
  => Data.Argonaut.Encode.EncodeJson a
  => Data.Argonaut.Decode.DecodeJson a
  => String
  -> a
  -> Replay.Common.TestResult
roundtripTest name value =
  let
    encoded = Data.Argonaut.Encode.encodeJson value
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right decodedValue ->
        if decodedValue == value then
          Replay.Common.TestSuccess name
        else
          Replay.Common.TestFailure name ("Roundtrip mismatch: got " <> show decodedValue)
      Data.Either.Left err ->
        Replay.Common.TestFailure name ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

roundtripTestShow
  :: forall a
   . Show a
  => Data.Argonaut.Encode.EncodeJson a
  => Data.Argonaut.Decode.DecodeJson a
  => String
  -> a
  -> Replay.Common.TestResult
roundtripTestShow name value =
  let
    encoded = Data.Argonaut.Encode.encodeJson value

    decoded :: Data.Either.Either Data.Argonaut.Decode.JsonDecodeError a
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right decodedValue ->
        if show decodedValue == show value then
          Replay.Common.TestSuccess name
        else
          Replay.Common.TestFailure name ("Roundtrip mismatch: got " <> show decodedValue)
      Data.Either.Left err ->
        Replay.Common.TestFailure name ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testStreamId :: Replay.Common.TestResult
testStreamId =
  roundtripTest "StreamId roundtrip" (Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV")

testTraceId :: Replay.Common.TestResult
testTraceId =
  roundtripTest "TraceId roundtrip" (Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV")

testEventSeq :: Replay.Common.TestResult
testEventSeq =
  roundtripTest "EventSeq roundtrip" (Replay.Protocol.Types.EventSeq 42)

testSiblingIndex :: Replay.Common.TestResult
testSiblingIndex =
  roundtripTest "SiblingIndex roundtrip" (Replay.Protocol.Types.SiblingIndex 0)

testEventTypeOpen :: Replay.Common.TestResult
testEventTypeOpen =
  roundtripTest "EventType Open roundtrip" Replay.Protocol.Types.EventTypeOpen

testEventTypeData :: Replay.Common.TestResult
testEventTypeData =
  roundtripTest "EventType Data roundtrip" Replay.Protocol.Types.EventTypeData

testEventTypeClose :: Replay.Common.TestResult
testEventTypeClose =
  roundtripTest "EventType Close roundtrip" Replay.Protocol.Types.EventTypeClose

-- | Helper to create a generic request payload
makeRequestPayload :: String -> Data.Argonaut.Core.Json -> Replay.Protocol.Types.RequestPayload
makeRequestPayload service payload = { service, payload }

-- | Helper to create a generic response payload
makeResponsePayload :: String -> Data.Argonaut.Core.Json -> Replay.Protocol.Types.ResponsePayload
makeResponsePayload service payload = { service, payload }

-- | Helper to create JSON object
makeObject :: Array (Data.Tuple.Tuple String Data.Argonaut.Core.Json) -> Data.Argonaut.Core.Json
makeObject pairs = Data.Argonaut.Core.fromObject (Foreign.Object.fromFoldable pairs)

testRequestPayloadBaml :: Replay.Common.TestResult
testRequestPayloadBaml =
  let
    payload = makeRequestPayload "baml"
      ( makeObject
          [ Data.Tuple.Tuple "functionName" (Data.Argonaut.Core.fromString "Answer")
          , Data.Tuple.Tuple "args" Data.Argonaut.Core.jsonEmptyObject
          , Data.Tuple.Tuple "templateHash" (Data.Argonaut.Core.fromString "abc123")
          ]
      )
    encoded = Data.Argonaut.Encode.encodeJson (Replay.Protocol.Types.CommandOpen payload)
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.CommandOpen decodedPayload) ->
        if decodedPayload.service == "baml" then
          Replay.Common.TestSuccess "RequestPayload Baml roundtrip"
        else
          Replay.Common.TestFailure "RequestPayload Baml roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "RequestPayload Baml roundtrip" "Got wrong command type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "RequestPayload Baml roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testRequestPayloadHttp :: Replay.Common.TestResult
testRequestPayloadHttp =
  let
    payload = makeRequestPayload "http"
      ( makeObject
          [ Data.Tuple.Tuple "method" (Data.Argonaut.Core.fromString "GET")
          , Data.Tuple.Tuple "url" (Data.Argonaut.Core.fromString "https://example.com/api")
          , Data.Tuple.Tuple "headers" (Data.Argonaut.Core.fromArray [])
          ]
      )
    encoded = Data.Argonaut.Encode.encodeJson (Replay.Protocol.Types.CommandOpen payload)
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.CommandOpen decodedPayload) ->
        if decodedPayload.service == "http" then
          Replay.Common.TestSuccess "RequestPayload Http roundtrip"
        else
          Replay.Common.TestFailure "RequestPayload Http roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "RequestPayload Http roundtrip" "Got wrong command type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "RequestPayload Http roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testRequestPayloadHttpWithBody :: Replay.Common.TestResult
testRequestPayloadHttpWithBody =
  let
    payload = makeRequestPayload "http"
      ( makeObject
          [ Data.Tuple.Tuple "method" (Data.Argonaut.Core.fromString "POST")
          , Data.Tuple.Tuple "url" (Data.Argonaut.Core.fromString "https://example.com/api")
          , Data.Tuple.Tuple "body" (Data.Argonaut.Core.fromString "{\"key\":\"value\"}")
          , Data.Tuple.Tuple "headers" (Data.Argonaut.Core.fromArray [])
          ]
      )
    encoded = Data.Argonaut.Encode.encodeJson (Replay.Protocol.Types.CommandOpen payload)
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.CommandOpen decodedPayload) ->
        if decodedPayload.service == "http" then
          Replay.Common.TestSuccess "RequestPayload Http with body roundtrip"
        else
          Replay.Common.TestFailure "RequestPayload Http with body roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "RequestPayload Http with body roundtrip" "Got wrong command type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "RequestPayload Http with body roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testRequestPayloadFileDownload :: Replay.Common.TestResult
testRequestPayloadFileDownload =
  let
    payload = makeRequestPayload "file_download"
      ( makeObject
          [ Data.Tuple.Tuple "url" (Data.Argonaut.Core.fromString "https://example.com/file.pdf")
          ]
      )
    encoded = Data.Argonaut.Encode.encodeJson (Replay.Protocol.Types.CommandOpen payload)
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.CommandOpen decodedPayload) ->
        if decodedPayload.service == "file_download" then
          Replay.Common.TestSuccess "RequestPayload FileDownload roundtrip"
        else
          Replay.Common.TestFailure "RequestPayload FileDownload roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "RequestPayload FileDownload roundtrip" "Got wrong command type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "RequestPayload FileDownload roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testRequestPayloadTextract :: Replay.Common.TestResult
testRequestPayloadTextract =
  let
    payload = makeRequestPayload "textract"
      ( makeObject
          [ Data.Tuple.Tuple "inputKey" (Data.Argonaut.Core.fromString "document.pdf")
          , Data.Tuple.Tuple "imageCount" (Data.Argonaut.Core.fromNumber 3.0)
          , Data.Tuple.Tuple "includeRawBlocks" (Data.Argonaut.Core.fromBoolean true)
          , Data.Tuple.Tuple "imagesBase64"
              ( Data.Argonaut.Core.fromArray
                  [ Data.Argonaut.Core.fromString "dGVzdCBpbWFnZSAxIGRhdGE="
                  , Data.Argonaut.Core.fromString "dGVzdCBpbWFnZSAyIGRhdGE="
                  , Data.Argonaut.Core.fromString "dGVzdCBpbWFnZSAzIGRhdGE="
                  ]
              )
          ]
      )
    encoded = Data.Argonaut.Encode.encodeJson (Replay.Protocol.Types.CommandOpen payload)
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.CommandOpen decodedPayload) ->
        if decodedPayload.service == "textract" then
          Replay.Common.TestSuccess "RequestPayload Textract roundtrip"
        else
          Replay.Common.TestFailure "RequestPayload Textract roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "RequestPayload Textract roundtrip" "Got wrong command type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "RequestPayload Textract roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testResponsePayloadBaml :: Replay.Common.TestResult
testResponsePayloadBaml =
  let
    payload = makeResponsePayload "baml"
      ( makeObject
          [ Data.Tuple.Tuple "result" Data.Argonaut.Core.jsonEmptyObject
          , Data.Tuple.Tuple "thinking" (Data.Argonaut.Core.fromString "thinking output")
          , Data.Tuple.Tuple "prompt" (Data.Argonaut.Core.fromString "the prompt")
          ]
      )
    event = Replay.Protocol.Types.EventClose payload
    encoded = Data.Argonaut.Encode.encodeJson event
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.EventClose decodedPayload) ->
        if decodedPayload.service == "baml" then
          Replay.Common.TestSuccess "ResponsePayload Baml roundtrip"
        else
          Replay.Common.TestFailure "ResponsePayload Baml roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "ResponsePayload Baml roundtrip" "Got wrong event type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "ResponsePayload Baml roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testResponsePayloadHttp :: Replay.Common.TestResult
testResponsePayloadHttp =
  let
    payload = makeResponsePayload "http"
      ( makeObject
          [ Data.Tuple.Tuple "statusCode" (Data.Argonaut.Core.fromNumber 200.0)
          , Data.Tuple.Tuple "body" (Data.Argonaut.Core.fromString "{\"success\":true}")
          ]
      )
    event = Replay.Protocol.Types.EventClose payload
    encoded = Data.Argonaut.Encode.encodeJson event
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.EventClose decodedPayload) ->
        if decodedPayload.service == "http" then
          Replay.Common.TestSuccess "ResponsePayload Http roundtrip"
        else
          Replay.Common.TestFailure "ResponsePayload Http roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "ResponsePayload Http roundtrip" "Got wrong event type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "ResponsePayload Http roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testResponsePayloadFileDownload :: Replay.Common.TestResult
testResponsePayloadFileDownload =
  let
    payload = makeResponsePayload "file_download"
      ( makeObject
          [ Data.Tuple.Tuple "contentBase64" (Data.Argonaut.Core.fromString "SGVsbG8gV29ybGQ=")
          ]
      )
    event = Replay.Protocol.Types.EventClose payload
    encoded = Data.Argonaut.Encode.encodeJson event
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.EventClose decodedPayload) ->
        if decodedPayload.service == "file_download" then
          Replay.Common.TestSuccess "ResponsePayload FileDownload roundtrip"
        else
          Replay.Common.TestFailure "ResponsePayload FileDownload roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "ResponsePayload FileDownload roundtrip" "Got wrong event type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "ResponsePayload FileDownload roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testResponsePayloadTextract :: Replay.Common.TestResult
testResponsePayloadTextract =
  let
    payload = makeResponsePayload "textract"
      ( makeObject
          [ Data.Tuple.Tuple "result" Data.Argonaut.Core.jsonEmptyObject
          ]
      )
    event = Replay.Protocol.Types.EventClose payload
    encoded = Data.Argonaut.Encode.encodeJson event
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.EventClose decodedPayload) ->
        if decodedPayload.service == "textract" then
          Replay.Common.TestSuccess "ResponsePayload Textract roundtrip"
        else
          Replay.Common.TestFailure "ResponsePayload Textract roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "ResponsePayload Textract roundtrip" "Got wrong event type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "ResponsePayload Textract roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testResponsePayloadError :: Replay.Common.TestResult
testResponsePayloadError =
  let
    payload = makeResponsePayload "error"
      ( makeObject
          [ Data.Tuple.Tuple "errorType" (Data.Argonaut.Core.fromString "BamlCallFailed")
          , Data.Tuple.Tuple "message" (Data.Argonaut.Core.fromString "Connection timeout")
          ]
      )
    event = Replay.Protocol.Types.EventClose payload
    encoded = Data.Argonaut.Encode.encodeJson event
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.EventClose decodedPayload) ->
        if decodedPayload.service == "error" then
          Replay.Common.TestSuccess "ResponsePayload Error roundtrip"
        else
          Replay.Common.TestFailure "ResponsePayload Error roundtrip" ("Wrong service: " <> decodedPayload.service)
      Data.Either.Right _ ->
        Replay.Common.TestFailure "ResponsePayload Error roundtrip" "Got wrong event type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "ResponsePayload Error roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testCommandOpen :: Replay.Common.TestResult
testCommandOpen =
  let
    payload = makeRequestPayload "http"
      ( makeObject
          [ Data.Tuple.Tuple "method" (Data.Argonaut.Core.fromString "GET")
          , Data.Tuple.Tuple "url" (Data.Argonaut.Core.fromString "https://example.com")
          , Data.Tuple.Tuple "headers" (Data.Argonaut.Core.fromArray [])
          ]
      )
    cmd = Replay.Protocol.Types.CommandOpen payload
    encoded = Data.Argonaut.Encode.encodeJson cmd
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.CommandOpen _) ->
        Replay.Common.TestSuccess "Command Open roundtrip"
      Data.Either.Right _ ->
        Replay.Common.TestFailure "Command Open roundtrip" "Got wrong command type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "Command Open roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testCommandClose :: Replay.Common.TestResult
testCommandClose =
  roundtripTestShow "Command Close roundtrip" Replay.Protocol.Types.CommandClose

testEventData :: Replay.Common.TestResult
testEventData =
  let
    event = Replay.Protocol.Types.EventData Data.Argonaut.Core.jsonEmptyObject
  in
    roundtripTest "Event Data roundtrip" event

testEventClose :: Replay.Common.TestResult
testEventClose =
  let
    payload = makeResponsePayload "http"
      ( makeObject
          [ Data.Tuple.Tuple "statusCode" (Data.Argonaut.Core.fromNumber 200.0)
          , Data.Tuple.Tuple "body" (Data.Argonaut.Core.fromString "OK")
          ]
      )
    event = Replay.Protocol.Types.EventClose payload
    encoded = Data.Argonaut.Encode.encodeJson event
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right (Replay.Protocol.Types.EventClose _) ->
        Replay.Common.TestSuccess "Event Close roundtrip"
      Data.Either.Right _ ->
        Replay.Common.TestFailure "Event Close roundtrip" "Got wrong event type"
      Data.Either.Left err ->
        Replay.Common.TestFailure "Event Close roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testEnvelopeCommand :: Replay.Common.TestResult
testEnvelopeCommand =
  let
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2025-01-08T12:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandClose
      }
  in
    roundtripTestShow "Envelope Command roundtrip" envelope

testEnvelopeWithCausation :: Replay.Common.TestResult
testEnvelopeWithCausation =
  let
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAW"
      , causationStreamId: Json.Nullable.jsonNotNull (Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAX")
      , parentStreamId: Json.Nullable.jsonNotNull (Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAY")
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 2
      , eventSeq: Replay.Protocol.Types.EventSeq 5
      , timestamp: "2025-01-08T12:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandClose
      }
  in
    roundtripTestShow "Envelope with causation roundtrip" envelope

testEnvelopeEvent :: Replay.Common.TestResult
testEnvelopeEvent =
  let
    payload = makeResponsePayload "baml"
      ( makeObject
          [ Data.Tuple.Tuple "result" Data.Argonaut.Core.jsonEmptyObject
          , Data.Tuple.Tuple "thinking" (Data.Argonaut.Core.fromString "")
          , Data.Tuple.Tuple "prompt" (Data.Argonaut.Core.fromString "test")
          ]
      )
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 1
      , timestamp: "2025-01-08T12:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.EventClose payload
      }
    encoded = Data.Argonaut.Encode.encodeJson envelope

    decoded :: Data.Either.Either Data.Argonaut.Decode.JsonDecodeError (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event)
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right _ ->
        Replay.Common.TestSuccess "Envelope Event roundtrip"
      Data.Either.Left err ->
        Replay.Common.TestFailure "Envelope Event roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

testEventTypeSerializesToCorrectString :: Replay.Common.TestResult
testEventTypeSerializesToCorrectString =
  let
    encoded = Data.Argonaut.Encode.encodeJson Replay.Protocol.Types.EventTypeOpen
    expected = Data.Argonaut.Core.fromString "open"
  in
    if encoded == expected then
      Replay.Common.TestSuccess "EventType serializes to correct string"
    else
      Replay.Common.TestFailure "EventType serializes to correct string" ("Expected 'open', got " <> Data.Argonaut.Core.stringify encoded)

testRequestPayloadIncludesServiceTag :: Replay.Common.TestResult
testRequestPayloadIncludesServiceTag =
  let
    payload = makeRequestPayload "baml"
      ( makeObject
          [ Data.Tuple.Tuple "functionName" (Data.Argonaut.Core.fromString "Test")
          , Data.Tuple.Tuple "args" Data.Argonaut.Core.jsonEmptyObject
          , Data.Tuple.Tuple "templateHash" (Data.Argonaut.Core.fromString "hash")
          ]
      )
    cmd = Replay.Protocol.Types.CommandOpen payload
    encoded = Data.Argonaut.Encode.encodeJson cmd
  in
    case Data.Argonaut.Core.toObject encoded of
      Data.Maybe.Just obj ->
        case Foreign.Object.lookup "payload" obj of
          Data.Maybe.Just payloadObj ->
            case Data.Argonaut.Core.toObject payloadObj of
              Data.Maybe.Just innerObj ->
                case Foreign.Object.lookup "service" innerObj of
                  Data.Maybe.Just svc ->
                    if svc == Data.Argonaut.Core.fromString "baml" then
                      Replay.Common.TestSuccess "RequestPayload includes service tag"
                    else
                      Replay.Common.TestFailure "RequestPayload includes service tag" ("Expected service 'baml', got " <> Data.Argonaut.Core.stringify svc)
                  Data.Maybe.Nothing ->
                    Replay.Common.TestFailure "RequestPayload includes service tag" "No service field found"
              Data.Maybe.Nothing ->
                Replay.Common.TestFailure "RequestPayload includes service tag" "Payload is not an object"
          Data.Maybe.Nothing ->
            Replay.Common.TestFailure "RequestPayload includes service tag" "No payload field found"
      Data.Maybe.Nothing ->
        Replay.Common.TestFailure "RequestPayload includes service tag" "Not an object"

testChannelProgramRoundtrip :: Replay.Common.TestResult
testChannelProgramRoundtrip =
  roundtripTest "Channel ProgramChannel roundtrip" Replay.Protocol.Types.ProgramChannel

testChannelPlatformRoundtrip :: Replay.Common.TestResult
testChannelPlatformRoundtrip =
  roundtripTest "Channel PlatformChannel roundtrip" Replay.Protocol.Types.PlatformChannel

testChannelProgramSerializesToCorrectString :: Replay.Common.TestResult
testChannelProgramSerializesToCorrectString =
  let
    encoded = Data.Argonaut.Encode.encodeJson Replay.Protocol.Types.ProgramChannel
    expected = Data.Argonaut.Core.fromString "program"
  in
    if encoded == expected then
      Replay.Common.TestSuccess "Channel ProgramChannel serializes to 'program'"
    else
      Replay.Common.TestFailure "Channel ProgramChannel serializes to 'program'" ("Expected 'program', got " <> Data.Argonaut.Core.stringify encoded)

testChannelPlatformSerializesToCorrectString :: Replay.Common.TestResult
testChannelPlatformSerializesToCorrectString =
  let
    encoded = Data.Argonaut.Encode.encodeJson Replay.Protocol.Types.PlatformChannel
    expected = Data.Argonaut.Core.fromString "platform"
  in
    if encoded == expected then
      Replay.Common.TestSuccess "Channel PlatformChannel serializes to 'platform'"
    else
      Replay.Common.TestFailure "Channel PlatformChannel serializes to 'platform'" ("Expected 'platform', got " <> Data.Argonaut.Core.stringify encoded)

testEnvelopeWithProgramChannel :: Replay.Common.TestResult
testEnvelopeWithProgramChannel =
  let
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2025-01-08T12:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandClose
      }
  in
    roundtripTestShow "Envelope with ProgramChannel roundtrip" envelope

testEnvelopeWithPlatformChannel :: Replay.Common.TestResult
testEnvelopeWithPlatformChannel =
  let
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2025-01-08T12:00:00.000Z"
      , channel: Replay.Protocol.Types.PlatformChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandClose
      }
  in
    roundtripTestShow "Envelope with PlatformChannel roundtrip" envelope

testEnvelopeChannelFieldIncludedInJson :: Replay.Common.TestResult
testEnvelopeChannelFieldIncludedInJson =
  let
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp: "2025-01-08T12:00:00.000Z"
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandClose
      }
    encoded = Data.Argonaut.Encode.encodeJson envelope
  in
    case Data.Argonaut.Core.toObject encoded of
      Data.Maybe.Just obj ->
        case Foreign.Object.lookup "channel" obj of
          Data.Maybe.Just channelValue ->
            if channelValue == Data.Argonaut.Core.fromString "program" then
              Replay.Common.TestSuccess "Envelope channel field included in JSON"
            else
              Replay.Common.TestFailure "Envelope channel field included in JSON" ("Expected channel 'program', got " <> Data.Argonaut.Core.stringify channelValue)
          Data.Maybe.Nothing ->
            Replay.Common.TestFailure "Envelope channel field included in JSON" "No channel field found"
      Data.Maybe.Nothing ->
        Replay.Common.TestFailure "Envelope channel field included in JSON" "Not an object"

testEnvelopeWithChannelAndCausation :: Replay.Common.TestResult
testEnvelopeWithChannelAndCausation =
  let
    payload = makeResponsePayload "baml"
      ( makeObject
          [ Data.Tuple.Tuple "result" Data.Argonaut.Core.jsonEmptyObject
          , Data.Tuple.Tuple "thinking" (Data.Argonaut.Core.fromString "")
          , Data.Tuple.Tuple "prompt" (Data.Argonaut.Core.fromString "test")
          ]
      )
    envelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAW"
      , causationStreamId: Json.Nullable.jsonNotNull (Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAX")
      , parentStreamId: Json.Nullable.jsonNotNull (Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAY")
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 2
      , eventSeq: Replay.Protocol.Types.EventSeq 5
      , timestamp: "2025-01-08T12:00:00.000Z"
      , channel: Replay.Protocol.Types.PlatformChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.EventClose payload
      }
    encoded = Data.Argonaut.Encode.encodeJson envelope

    decoded :: Data.Either.Either Data.Argonaut.Decode.JsonDecodeError (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event)
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right _ ->
        Replay.Common.TestSuccess "Envelope with channel and causation roundtrip"
      Data.Either.Left err ->
        Replay.Common.TestFailure "Envelope with channel and causation roundtrip" ("Decode failed: " <> Data.Argonaut.Decode.printJsonDecodeError err)

allTests :: Array Replay.Common.TestResult
allTests =
  [ testStreamId
  , testTraceId
  , testEventSeq
  , testSiblingIndex
  , testEventTypeOpen
  , testEventTypeData
  , testEventTypeClose
  , testRequestPayloadBaml
  , testRequestPayloadHttp
  , testRequestPayloadHttpWithBody
  , testRequestPayloadFileDownload
  , testRequestPayloadTextract
  , testResponsePayloadBaml
  , testResponsePayloadHttp
  , testResponsePayloadFileDownload
  , testResponsePayloadTextract
  , testResponsePayloadError
  , testCommandOpen
  , testCommandClose
  , testEventData
  , testEventClose
  , testEnvelopeCommand
  , testEnvelopeWithCausation
  , testEnvelopeEvent
  , testEventTypeSerializesToCorrectString
  , testRequestPayloadIncludesServiceTag
  , testChannelProgramRoundtrip
  , testChannelPlatformRoundtrip
  , testChannelProgramSerializesToCorrectString
  , testChannelPlatformSerializesToCorrectString
  , testEnvelopeWithProgramChannel
  , testEnvelopeWithPlatformChannel
  , testEnvelopeChannelFieldIncludedInJson
  , testEnvelopeWithChannelAndCausation
  ]

runTests :: Replay.Common.TestResults
runTests = Replay.Common.computeResults allTests
