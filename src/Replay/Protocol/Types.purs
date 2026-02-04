module Replay.Protocol.Types
  ( StreamId(..)
  , TraceId(..)
  , EventSeq(..)
  , SiblingIndex(..)
  , EventType(..)
  , Channel(..)
  , RequestPayload
  , ResponsePayload
  , ErrorPayload
  , Command(..)
  , Event(..)
  , Envelope(..)
  , RequestId(..)
  , ControlEnvelope
  , ControlCommand(..)
  , ControlResponse(..)
  , ControlErrorType(..)
  , MessageFilter
  , UrlMatch(..)
  , InterceptId(..)
  , InterceptSpec
  , InterceptMatch
  , InterceptInfo
  , Milliseconds(..)
  , HarnessStatus
  , HarnessMode(..)
  , MessageDirection(..)
  , SessionId(..)
  , SessionConfig
  , SessionError(..)
  , mkRequestPayload
  , mkResponsePayload
  , getService
  , getPayload
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Decode (class DecodeJson, (.:), (.:?))
import Data.Argonaut.Decode.Error as Data.Argonaut.Decode.Error
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Argonaut.Encode (class EncodeJson, (:=), (~>))
import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Maybe as Data.Maybe
import Data.Newtype as Data.Newtype
import Data.Traversable as Data.Traversable
import Foreign.Object as Foreign.Object
import Json.Nullable as Json.Nullable
import Replay.Types (HarnessMode(..)) as Replay.Types

newtype StreamId = StreamId String

derive instance Data.Newtype.Newtype StreamId _
derive instance Eq StreamId
derive instance Ord StreamId
derive newtype instance Show StreamId

instance EncodeJson StreamId where
  encodeJson (StreamId s) = Data.Argonaut.Encode.encodeJson s

instance DecodeJson StreamId where
  decodeJson json = StreamId <$> Data.Argonaut.Decode.decodeJson json

newtype TraceId = TraceId String

derive instance Data.Newtype.Newtype TraceId _
derive instance Eq TraceId
derive instance Ord TraceId
derive newtype instance Show TraceId

instance EncodeJson TraceId where
  encodeJson (TraceId s) = Data.Argonaut.Encode.encodeJson s

instance DecodeJson TraceId where
  decodeJson json = TraceId <$> Data.Argonaut.Decode.decodeJson json

newtype EventSeq = EventSeq Int

derive instance Data.Newtype.Newtype EventSeq _
derive instance Eq EventSeq
derive instance Ord EventSeq
derive newtype instance Show EventSeq

instance EncodeJson EventSeq where
  encodeJson (EventSeq n) = Data.Argonaut.Encode.encodeJson n

instance DecodeJson EventSeq where
  decodeJson json = EventSeq <$> Data.Argonaut.Decode.decodeJson json

newtype SiblingIndex = SiblingIndex Int

derive instance Data.Newtype.Newtype SiblingIndex _
derive instance Eq SiblingIndex
derive instance Ord SiblingIndex
derive newtype instance Show SiblingIndex

instance EncodeJson SiblingIndex where
  encodeJson (SiblingIndex n) = Data.Argonaut.Encode.encodeJson n

instance DecodeJson SiblingIndex where
  decodeJson json = SiblingIndex <$> Data.Argonaut.Decode.decodeJson json

data EventType
  = EventTypeOpen
  | EventTypeData
  | EventTypeClose

derive instance Eq EventType
derive instance Ord EventType

instance Show EventType where
  show EventTypeOpen = "EventTypeOpen"
  show EventTypeData = "EventTypeData"
  show EventTypeClose = "EventTypeClose"

instance EncodeJson EventType where
  encodeJson EventTypeOpen = Data.Argonaut.Encode.encodeJson "open"
  encodeJson EventTypeData = Data.Argonaut.Encode.encodeJson "data"
  encodeJson EventTypeClose = Data.Argonaut.Encode.encodeJson "close"

instance DecodeJson EventType where
  decodeJson json = do
    str <- Data.Argonaut.Decode.decodeJson json
    case str of
      "open" -> Data.Either.Right EventTypeOpen
      "data" -> Data.Either.Right EventTypeData
      "close" -> Data.Either.Right EventTypeClose
      other -> Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown event type: " <> other))

data Channel
  = ProgramChannel
  | PlatformChannel
  | ControlChannel

derive instance Eq Channel
derive instance Ord Channel

instance Show Channel where
  show ProgramChannel = "ProgramChannel"
  show PlatformChannel = "PlatformChannel"
  show ControlChannel = "ControlChannel"

instance EncodeJson Channel where
  encodeJson ProgramChannel = Data.Argonaut.Encode.encodeJson "program"
  encodeJson PlatformChannel = Data.Argonaut.Encode.encodeJson "platform"
  encodeJson ControlChannel = Data.Argonaut.Encode.encodeJson "control"

instance DecodeJson Channel where
  decodeJson json = do
    str <- Data.Argonaut.Decode.decodeJson json
    case str of
      "program" -> Data.Either.Right ProgramChannel
      "platform" -> Data.Either.Right PlatformChannel
      "control" -> Data.Either.Right ControlChannel
      other -> Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown channel: " <> other))

-- | Generic request payload - the harness doesn't care about the specific service types.
-- | Applications define their own service types and serialize them to this format.
-- | The harness just hashes the JSON and stores/retrieves it.
type RequestPayload =
  { service :: String
  , payload :: Data.Argonaut.Core.Json
  }

-- | Generic response payload - the harness doesn't care about the specific service types.
-- | Applications define their own response types and deserialize from this format.
type ResponsePayload =
  { service :: String
  , payload :: Data.Argonaut.Core.Json
  }

-- | Helper to construct a request payload
mkRequestPayload :: String -> Data.Argonaut.Core.Json -> RequestPayload
mkRequestPayload service payload = { service, payload }

-- | Helper to construct a response payload
mkResponsePayload :: String -> Data.Argonaut.Core.Json -> ResponsePayload
mkResponsePayload service payload = { service, payload }

-- | Get the service name from a request payload
getService :: RequestPayload -> String
getService p = p.service

-- | Get the payload JSON from a request payload
getPayload :: RequestPayload -> Data.Argonaut.Core.Json
getPayload p = p.payload

type ErrorPayload =
  { errorType :: String
  , message :: String
  }

data Command
  = CommandOpen RequestPayload
  | CommandClose

instance Show Command where
  show (CommandOpen payload) = "CommandOpen { service: " <> show payload.service <> " }"
  show CommandClose = "CommandClose"

instance EncodeJson Command where
  encodeJson (CommandOpen payload) =
    "type" := ("open" :: String)
      ~> "payload" := encodeRequestPayload payload
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson CommandClose =
    "type" := ("close" :: String)
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson Command where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    cmdType :: String <- obj .: "type"
    case cmdType of
      "open" -> do
        payloadJson <- obj .: "payload"
        payload <- decodeRequestPayload payloadJson
        Data.Either.Right $ CommandOpen payload
      "close" -> do
        maybePayload :: Data.Maybe.Maybe Data.Argonaut.Core.Json <- obj .:? "payload"
        case maybePayload of
          Data.Maybe.Nothing ->
            Data.Either.Right CommandClose
          Data.Maybe.Just _ ->
            Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch "CommandClose must not have payload (this looks like EventClose)")
      other ->
        Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown command type: " <> other))

data Event
  = EventData Data.Argonaut.Core.Json
  | EventClose ResponsePayload

instance Eq Event where
  eq (EventData a) (EventData b) = a == b
  eq (EventClose a) (EventClose b) = a.service == b.service && a.payload == b.payload
  eq _ _ = false

instance Show Event where
  show (EventData _) = "EventData <json>"
  show (EventClose payload) = "EventClose { service: " <> show payload.service <> " }"

instance EncodeJson Event where
  encodeJson (EventData payload) =
    "type" := ("data" :: String)
      ~> "payload" := payload
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (EventClose payload) =
    "type" := ("close" :: String)
      ~> "payload" := encodeResponsePayload payload
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson Event where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    eventType :: String <- obj .: "type"
    case eventType of
      "data" -> do
        payload <- obj .: "payload"
        Data.Either.Right $ EventData payload
      "close" -> do
        payloadJson <- obj .: "payload"
        payload <- decodeResponsePayload payloadJson
        Data.Either.Right $ EventClose payload
      other ->
        Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown event type: " <> other))

newtype Envelope a = Envelope
  { streamId :: StreamId
  , traceId :: TraceId
  , causationStreamId :: Json.Nullable.JsonNullable StreamId
  , parentStreamId :: Json.Nullable.JsonNullable StreamId
  , siblingIndex :: SiblingIndex
  , eventSeq :: EventSeq
  , timestamp :: String
  , channel :: Channel
  , payloadHash :: Data.Maybe.Maybe String
  , payload :: a
  }

derive instance Data.Newtype.Newtype (Envelope a) _

instance Eq a => Eq (Envelope a) where
  eq (Envelope a) (Envelope b) =
    a.streamId == b.streamId
      && a.traceId == b.traceId
      && a.causationStreamId == b.causationStreamId
      && a.parentStreamId == b.parentStreamId
      && a.siblingIndex == b.siblingIndex
      && a.eventSeq == b.eventSeq
      && a.timestamp == b.timestamp
      && a.channel == b.channel
      && a.payloadHash == b.payloadHash
      && a.payload == b.payload

instance Show a => Show (Envelope a) where
  show (Envelope env) = "Envelope { streamId: " <> show env.streamId <> ", traceId: " <> show env.traceId <> ", siblingIndex: " <> show env.siblingIndex <> ", eventSeq: " <> show env.eventSeq <> ", timestamp: " <> show env.timestamp <> ", channel: " <> show env.channel <> ", payloadHash: " <> show env.payloadHash <> ", payload: " <> show env.payload <> " }"

instance EncodeJson a => EncodeJson (Envelope a) where
  encodeJson (Envelope env) =
    "streamId" := env.streamId
      ~> "traceId" := env.traceId
      ~> "causationStreamId" := env.causationStreamId
      ~> "parentStreamId" := env.parentStreamId
      ~> "siblingIndex" := env.siblingIndex
      ~> "eventSeq" := env.eventSeq
      ~> "timestamp" := env.timestamp
      ~> "channel" := env.channel
      ~> "payloadHash" := env.payloadHash
      ~> "payload" := env.payload
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson a => DecodeJson (Envelope a) where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    streamId <- obj .: "streamId"
    traceId <- obj .: "traceId"
    causationStreamId <- obj .:? "causationStreamId"
    parentStreamId <- obj .:? "parentStreamId"
    siblingIndex <- obj .: "siblingIndex"
    eventSeq <- obj .: "eventSeq"
    timestamp <- obj .: "timestamp"
    channel <- obj .: "channel"
    payloadHash <- obj .:? "payloadHash"
    payload <- obj .: "payload"
    Data.Either.Right $ Envelope
      { streamId
      , traceId
      , causationStreamId: Data.Maybe.fromMaybe Json.Nullable.jsonNull causationStreamId
      , parentStreamId: Data.Maybe.fromMaybe Json.Nullable.jsonNull parentStreamId
      , siblingIndex
      , eventSeq
      , timestamp
      , channel
      , payloadHash: Data.Maybe.fromMaybe Data.Maybe.Nothing payloadHash
      , payload
      }

newtype RequestId = RequestId String

derive instance Data.Newtype.Newtype RequestId _
derive instance Eq RequestId
derive instance Ord RequestId
derive newtype instance Show RequestId

instance EncodeJson RequestId where
  encodeJson (RequestId s) = Data.Argonaut.Encode.encodeJson s

instance DecodeJson RequestId where
  decodeJson json = RequestId <$> Data.Argonaut.Decode.decodeJson json

type ControlEnvelope =
  { requestId :: RequestId
  , payload :: ControlCommand
  }

data MessageDirection
  = ToHarness
  | FromHarness

derive instance Eq MessageDirection
derive instance Ord MessageDirection

instance Show MessageDirection where
  show ToHarness = "ToHarness"
  show FromHarness = "FromHarness"

instance EncodeJson MessageDirection where
  encodeJson ToHarness = Data.Argonaut.Encode.encodeJson "to_harness"
  encodeJson FromHarness = Data.Argonaut.Encode.encodeJson "from_harness"

instance DecodeJson MessageDirection where
  decodeJson json = do
    str <- Data.Argonaut.Decode.decodeJson json
    case str of
      "to_harness" -> Data.Either.Right ToHarness
      "from_harness" -> Data.Either.Right FromHarness
      other -> Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown message direction: " <> other))

data UrlMatch
  = UrlExact String
  | UrlContains String

derive instance Eq UrlMatch
derive instance Ord UrlMatch

instance Show UrlMatch where
  show (UrlExact s) = "UrlExact " <> show s
  show (UrlContains s) = "UrlContains " <> show s

instance EncodeJson UrlMatch where
  encodeJson (UrlExact s) =
    "type" := ("exact" :: String)
      ~> "value" := s
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (UrlContains s) =
    "type" := ("contains" :: String)
      ~> "value" := s
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson UrlMatch where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    matchType :: String <- obj .: "type"
    value <- obj .: "value"
    case matchType of
      "exact" -> Data.Either.Right (UrlExact value)
      "contains" -> Data.Either.Right (UrlContains value)
      other -> Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown URL match type: " <> other))

-- | Generic message filter - uses String for service type since harness is agnostic
type MessageFilter =
  { service :: Data.Maybe.Maybe String
  , direction :: Data.Maybe.Maybe MessageDirection
  , functionName :: Data.Maybe.Maybe String
  , urlMatch :: Data.Maybe.Maybe UrlMatch
  , method :: Data.Maybe.Maybe String
  , payloadContains :: Data.Maybe.Maybe String
  }

newtype InterceptId = InterceptId String

derive instance Data.Newtype.Newtype InterceptId _
derive instance Eq InterceptId
derive instance Ord InterceptId
derive newtype instance Show InterceptId

instance EncodeJson InterceptId where
  encodeJson (InterceptId s) = Data.Argonaut.Encode.encodeJson s

instance DecodeJson InterceptId where
  decodeJson json = InterceptId <$> Data.Argonaut.Decode.decodeJson json

newtype Milliseconds = Milliseconds Int

derive instance Data.Newtype.Newtype Milliseconds _
derive instance Eq Milliseconds
derive instance Ord Milliseconds
derive newtype instance Show Milliseconds

instance EncodeJson Milliseconds where
  encodeJson (Milliseconds n) = Data.Argonaut.Encode.encodeJson n

instance DecodeJson Milliseconds where
  decodeJson json = Milliseconds <$> Data.Argonaut.Decode.decodeJson json

-- | Generic intercept match - uses String for service type since harness is agnostic
type InterceptMatch =
  { service :: String
  , functionName :: Data.Maybe.Maybe String
  , urlMatch :: Data.Maybe.Maybe UrlMatch
  , method :: Data.Maybe.Maybe String
  }

type InterceptSpec =
  { match :: InterceptMatch
  , response :: ResponsePayload
  , priority :: Int
  , times :: Data.Maybe.Maybe Int
  , delay :: Data.Maybe.Maybe Milliseconds
  }

type InterceptInfo =
  { interceptId :: InterceptId
  , spec :: InterceptSpec
  , matchCount :: Int
  , remainingMatches :: Data.Maybe.Maybe Int
  }

type HarnessMode = Replay.Types.HarnessMode

type HarnessStatus =
  { mode :: HarnessMode
  , recordedMessageCount :: Int
  , activeInterceptCount :: Int
  , pendingRequestCount :: Int
  }

newtype SessionId = SessionId String

derive instance Data.Newtype.Newtype SessionId _
derive instance Eq SessionId
derive instance Ord SessionId

instance Show SessionId where
  show (SessionId s) = "SessionId " <> show s

instance EncodeJson SessionId where
  encodeJson (SessionId s) = Data.Argonaut.Encode.encodeJson s

instance DecodeJson SessionId where
  decodeJson json = SessionId <$> Data.Argonaut.Decode.decodeJson json

type SessionConfig =
  { sessionId :: SessionId
  , mode :: HarnessMode
  , recordingPath :: Data.Maybe.Maybe String
  }

data SessionError
  = SessionAlreadyExists SessionId
  | SessionNotFound SessionId
  | RecordingLoadFailed String

derive instance Eq SessionError

instance Show SessionError where
  show (SessionAlreadyExists sessionId) = "SessionAlreadyExists: " <> show sessionId
  show (SessionNotFound sessionId) = "SessionNotFound: " <> show sessionId
  show (RecordingLoadFailed reason) = "RecordingLoadFailed: " <> reason

instance EncodeJson SessionError where
  encodeJson (SessionAlreadyExists sessionId) =
    "type" := ("session_already_exists" :: String)
      ~> "sessionId" := sessionId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (SessionNotFound sessionId) =
    "type" := ("session_not_found" :: String)
      ~> "sessionId" := sessionId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (RecordingLoadFailed reason) =
    "type" := ("recording_load_failed" :: String)
      ~> "reason" := reason
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson SessionError where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    errorType :: String <- obj .: "type"
    case errorType of
      "session_already_exists" -> do
        sessionId <- obj .: "sessionId"
        Data.Either.Right (SessionAlreadyExists sessionId)
      "session_not_found" -> do
        sessionId <- obj .: "sessionId"
        Data.Either.Right (SessionNotFound sessionId)
      "recording_load_failed" -> do
        reason <- obj .: "reason"
        Data.Either.Right (RecordingLoadFailed reason)
      other ->
        Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown session error type: " <> other))

data ControlErrorType
  = InvalidFilter String
  | InvalidRegex String
  | InternalError String

derive instance Eq ControlErrorType
derive instance Ord ControlErrorType

instance Show ControlErrorType where
  show (InvalidFilter s) = "InvalidFilter " <> show s
  show (InvalidRegex s) = "InvalidRegex " <> show s
  show (InternalError s) = "InternalError " <> show s

instance EncodeJson ControlErrorType where
  encodeJson (InvalidFilter msg) =
    "type" := ("invalid_filter" :: String)
      ~> "message" := msg
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (InvalidRegex msg) =
    "type" := ("invalid_regex" :: String)
      ~> "message" := msg
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (InternalError msg) =
    "type" := ("internal_error" :: String)
      ~> "message" := msg
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson ControlErrorType where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    errorType :: String <- obj .: "type"
    msg <- obj .: "message"
    case errorType of
      "invalid_filter" -> Data.Either.Right (InvalidFilter msg)
      "invalid_regex" -> Data.Either.Right (InvalidRegex msg)
      "internal_error" -> Data.Either.Right (InternalError msg)
      other -> Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown control error type: " <> other))

data ControlCommand
  = GetMessages MessageFilter
  | GetMessageCount MessageFilter
  | GetStatus
  | RegisterIntercept InterceptSpec
  | RemoveIntercept InterceptId
  | ClearIntercepts (Data.Maybe.Maybe String)
  | ListIntercepts
  | GetInterceptStats InterceptId
  | CreateSession SessionConfig
  | CloseSession SessionId
  | ListSessions

derive instance Eq ControlCommand

instance Show ControlCommand where
  show (GetMessages _) = "GetMessages <filter>"
  show (GetMessageCount _) = "GetMessageCount <filter>"
  show GetStatus = "GetStatus"
  show (RegisterIntercept _) = "RegisterIntercept <spec>"
  show (RemoveIntercept id) = "RemoveIntercept " <> show id
  show (ClearIntercepts svc) = "ClearIntercepts " <> show svc
  show ListIntercepts = "ListIntercepts"
  show (GetInterceptStats id) = "GetInterceptStats " <> show id
  show (CreateSession config) = "CreateSession " <> show config.sessionId
  show (CloseSession sessionId) = "CloseSession " <> show sessionId
  show ListSessions = "ListSessions"

instance EncodeJson ControlCommand where
  encodeJson (GetMessages filter) =
    "command" := ("get_messages" :: String)
      ~> "filter" := encodeMessageFilter filter
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (GetMessageCount filter) =
    "command" := ("get_message_count" :: String)
      ~> "filter" := encodeMessageFilter filter
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson GetStatus =
    "command" := ("get_status" :: String)
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (RegisterIntercept spec) =
    "command" := ("register_intercept" :: String)
      ~> "spec" := encodeInterceptSpec spec
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (RemoveIntercept interceptId) =
    "command" := ("remove_intercept" :: String)
      ~> "interceptId" := interceptId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (ClearIntercepts maybeService) =
    "command" := ("clear_intercepts" :: String)
      ~> "service" := maybeService
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson ListIntercepts =
    "command" := ("list_intercepts" :: String)
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (GetInterceptStats interceptId) =
    "command" := ("get_intercept_stats" :: String)
      ~> "interceptId" := interceptId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (CreateSession config) =
    "command" := ("create_session" :: String)
      ~> "config" := encodeSessionConfig config
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (CloseSession sessionId) =
    "command" := ("close_session" :: String)
      ~> "sessionId" := sessionId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson ListSessions =
    "command" := ("list_sessions" :: String)
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson ControlCommand where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    cmd :: String <- obj .: "command"
    case cmd of
      "get_messages" -> do
        filter <- obj .: "filter"
        filterRecord <- decodeMessageFilter filter
        Data.Either.Right (GetMessages filterRecord)
      "get_message_count" -> do
        filter <- obj .: "filter"
        filterRecord <- decodeMessageFilter filter
        Data.Either.Right (GetMessageCount filterRecord)
      "get_status" ->
        Data.Either.Right GetStatus
      "register_intercept" -> do
        specJson <- obj .: "spec"
        spec <- decodeInterceptSpec specJson
        Data.Either.Right (RegisterIntercept spec)
      "remove_intercept" -> do
        interceptId <- obj .: "interceptId"
        Data.Either.Right (RemoveIntercept interceptId)
      "clear_intercepts" -> do
        maybeService <- obj .:? "service"
        Data.Either.Right (ClearIntercepts (Data.Maybe.fromMaybe Data.Maybe.Nothing maybeService))
      "list_intercepts" ->
        Data.Either.Right ListIntercepts
      "get_intercept_stats" -> do
        interceptId <- obj .: "interceptId"
        Data.Either.Right (GetInterceptStats interceptId)
      "create_session" -> do
        configJson <- obj .: "config"
        config <- decodeSessionConfig configJson
        Data.Either.Right (CreateSession config)
      "close_session" -> do
        sessionId <- obj .: "sessionId"
        Data.Either.Right (CloseSession sessionId)
      "list_sessions" ->
        Data.Either.Right ListSessions
      other ->
        Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown control command: " <> other))

data ControlResponse
  = MessagesResult (Array Data.Argonaut.Core.Json)
  | CountResult Int
  | StatusResult HarnessStatus
  | InterceptRegistered InterceptId
  | InterceptRemoved Boolean
  | InterceptsCleared Int
  | InterceptList (Array InterceptInfo)
  | InterceptStatsResult { matchCount :: Int }
  | ControlError ControlErrorType
  | SessionCreated SessionId
  | SessionClosed SessionId
  | SessionList (Array SessionId)
  | SessionError SessionError

derive instance Eq ControlResponse

instance Show ControlResponse where
  show (MessagesResult msgs) = "MessagesResult [" <> show (Data.Array.length msgs) <> " messages]"
  show (CountResult n) = "CountResult " <> show n
  show (StatusResult _) = "StatusResult <status>"
  show (InterceptRegistered id) = "InterceptRegistered " <> show id
  show (InterceptRemoved removed) = "InterceptRemoved " <> show removed
  show (InterceptsCleared n) = "InterceptsCleared " <> show n
  show (InterceptList infos) = "InterceptList [" <> show (Data.Array.length infos) <> " intercepts]"
  show (InterceptStatsResult stats) = "InterceptStatsResult { matchCount: " <> show stats.matchCount <> " }"
  show (ControlError err) = "ControlError " <> show err
  show (SessionCreated sessionId) = "SessionCreated " <> show sessionId
  show (SessionClosed sessionId) = "SessionClosed " <> show sessionId
  show (SessionList sessions) = "SessionList [" <> show (Data.Array.length sessions) <> " sessions]"
  show (SessionError err) = "SessionError " <> show err

instance EncodeJson ControlResponse where
  encodeJson (MessagesResult msgs) =
    "response" := ("messages" :: String)
      ~> "messages" := msgs
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (CountResult count) =
    "response" := ("count" :: String)
      ~> "count" := count
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (StatusResult status) =
    "response" := ("status" :: String)
      ~> "status" := encodeHarnessStatus status
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (InterceptRegistered interceptId) =
    "response" := ("intercept_registered" :: String)
      ~> "interceptId" := interceptId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (InterceptRemoved removed) =
    "response" := ("intercept_removed" :: String)
      ~> "removed" := removed
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (InterceptsCleared count) =
    "response" := ("intercepts_cleared" :: String)
      ~> "count" := count
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (InterceptList infos) =
    "response" := ("intercept_list" :: String)
      ~> "intercepts" := map encodeInterceptInfo infos
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (InterceptStatsResult stats) =
    "response" := ("intercept_stats" :: String)
      ~> "matchCount" := stats.matchCount
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (ControlError err) =
    "response" := ("error" :: String)
      ~> "error" := err
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (SessionCreated sessionId) =
    "response" := ("session_created" :: String)
      ~> "sessionId" := sessionId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (SessionClosed sessionId) =
    "response" := ("session_closed" :: String)
      ~> "sessionId" := sessionId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (SessionList sessions) =
    "response" := ("session_list" :: String)
      ~> "sessions" := sessions
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (SessionError err) =
    "response" := ("session_error" :: String)
      ~> "error" := err
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson ControlResponse where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    resp :: String <- obj .: "response"
    case resp of
      "messages" -> do
        msgs <- obj .: "messages"
        Data.Either.Right (MessagesResult msgs)
      "count" -> do
        count <- obj .: "count"
        Data.Either.Right (CountResult count)
      "status" -> do
        statusJson <- obj .: "status"
        status <- decodeHarnessStatus statusJson
        Data.Either.Right (StatusResult status)
      "intercept_registered" -> do
        interceptId <- obj .: "interceptId"
        Data.Either.Right (InterceptRegistered interceptId)
      "intercept_removed" -> do
        removed <- obj .: "removed"
        Data.Either.Right (InterceptRemoved removed)
      "intercepts_cleared" -> do
        count <- obj .: "count"
        Data.Either.Right (InterceptsCleared count)
      "intercept_list" -> do
        interceptsJson <- obj .: "intercepts"
        intercepts <- Data.Traversable.traverse decodeInterceptInfo interceptsJson
        Data.Either.Right (InterceptList intercepts)
      "intercept_stats" -> do
        matchCount <- obj .: "matchCount"
        Data.Either.Right (InterceptStatsResult { matchCount })
      "error" -> do
        err <- obj .: "error"
        Data.Either.Right (ControlError err)
      "session_created" -> do
        sessionId <- obj .: "sessionId"
        Data.Either.Right (SessionCreated sessionId)
      "session_closed" -> do
        sessionId <- obj .: "sessionId"
        Data.Either.Right (SessionClosed sessionId)
      "session_list" -> do
        sessions <- obj .: "sessions"
        Data.Either.Right (SessionList sessions)
      "session_error" -> do
        err <- obj .: "error"
        Data.Either.Right (SessionError err)
      other ->
        Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown control response: " <> other))

-- Helper encoders/decoders for generic payloads

encodeRequestPayload :: RequestPayload -> Data.Argonaut.Core.Json
encodeRequestPayload payload =
  "service" := payload.service
    ~> "payload" := payload.payload
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeRequestPayload :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError RequestPayload
decodeRequestPayload json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  service <- obj .: "service"
  payload <- obj .: "payload"
  Data.Either.Right { service, payload }

encodeResponsePayload :: ResponsePayload -> Data.Argonaut.Core.Json
encodeResponsePayload payload =
  "service" := payload.service
    ~> "payload" := payload.payload
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeResponsePayload :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError ResponsePayload
decodeResponsePayload json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  service <- obj .: "service"
  -- Support both formats:
  -- 1. {service, payload: {...}} - replay canonical format
  -- 2. {service, field1, field2, ...} - oz legacy format (entire object is the payload)
  maybePayload <- obj .:? "payload"
  let
    payload = case maybePayload of
      Data.Maybe.Just p -> p
      Data.Maybe.Nothing -> json -- Use entire JSON object as payload
  Data.Either.Right { service, payload }

encodeMessageFilter :: MessageFilter -> Data.Argonaut.Core.Json
encodeMessageFilter filter =
  "service" := filter.service
    ~> "direction" := filter.direction
    ~> "functionName" := filter.functionName
    ~> "urlMatch" := filter.urlMatch
    ~> "method" := filter.method
    ~> "payloadContains" := filter.payloadContains
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeMessageFilter :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError MessageFilter
decodeMessageFilter json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  service <- obj .:? "service"
  direction <- obj .:? "direction"
  functionName <- obj .:? "functionName"
  urlMatch <- obj .:? "urlMatch"
  method <- obj .:? "method"
  payloadContains <- obj .:? "payloadContains"
  Data.Either.Right
    { service: Data.Maybe.fromMaybe Data.Maybe.Nothing service
    , direction: Data.Maybe.fromMaybe Data.Maybe.Nothing direction
    , functionName: Data.Maybe.fromMaybe Data.Maybe.Nothing functionName
    , urlMatch: Data.Maybe.fromMaybe Data.Maybe.Nothing urlMatch
    , method: Data.Maybe.fromMaybe Data.Maybe.Nothing method
    , payloadContains: Data.Maybe.fromMaybe Data.Maybe.Nothing payloadContains
    }

encodeInterceptMatch :: InterceptMatch -> Data.Argonaut.Core.Json
encodeInterceptMatch match =
  "service" := match.service
    ~> "functionName" := match.functionName
    ~> "urlMatch" := match.urlMatch
    ~> "method" := match.method
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeInterceptMatch :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError InterceptMatch
decodeInterceptMatch json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  service <- obj .: "service"
  functionName <- obj .:? "functionName"
  urlMatch <- obj .:? "urlMatch"
  method <- obj .:? "method"
  Data.Either.Right
    { service
    , functionName: Data.Maybe.fromMaybe Data.Maybe.Nothing functionName
    , urlMatch: Data.Maybe.fromMaybe Data.Maybe.Nothing urlMatch
    , method: Data.Maybe.fromMaybe Data.Maybe.Nothing method
    }

encodeInterceptSpec :: InterceptSpec -> Data.Argonaut.Core.Json
encodeInterceptSpec spec =
  "match" := encodeInterceptMatch spec.match
    ~> "response" := encodeResponsePayload spec.response
    ~> "priority" := spec.priority
    ~> "times" := spec.times
    ~> "delay" := spec.delay
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeInterceptSpec :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError InterceptSpec
decodeInterceptSpec json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  matchJson <- obj .: "match"
  match <- decodeInterceptMatch matchJson
  responseJson <- obj .: "response"
  response <- decodeResponsePayload responseJson
  priority <- obj .: "priority"
  times <- obj .:? "times"
  delay <- obj .:? "delay"
  Data.Either.Right
    { match
    , response
    , priority
    , times: Data.Maybe.fromMaybe Data.Maybe.Nothing times
    , delay: Data.Maybe.fromMaybe Data.Maybe.Nothing delay
    }

encodeInterceptInfo :: InterceptInfo -> Data.Argonaut.Core.Json
encodeInterceptInfo info =
  "interceptId" := info.interceptId
    ~> "spec" := encodeInterceptSpec info.spec
    ~> "matchCount" := info.matchCount
    ~> "remainingMatches" := info.remainingMatches
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeInterceptInfo :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError InterceptInfo
decodeInterceptInfo json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  interceptId <- obj .: "interceptId"
  specJson <- obj .: "spec"
  spec <- decodeInterceptSpec specJson
  matchCount <- obj .: "matchCount"
  remainingMatches <- obj .:? "remainingMatches"
  Data.Either.Right
    { interceptId
    , spec
    , matchCount
    , remainingMatches: Data.Maybe.fromMaybe Data.Maybe.Nothing remainingMatches
    }

encodeHarnessStatus :: HarnessStatus -> Data.Argonaut.Core.Json
encodeHarnessStatus status =
  "mode" := status.mode
    ~> "recordedMessageCount" := status.recordedMessageCount
    ~> "activeInterceptCount" := status.activeInterceptCount
    ~> "pendingRequestCount" := status.pendingRequestCount
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeHarnessStatus :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError HarnessStatus
decodeHarnessStatus json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  mode <- obj .: "mode"
  recordedMessageCount <- obj .: "recordedMessageCount"
  activeInterceptCount <- obj .: "activeInterceptCount"
  pendingRequestCount <- obj .: "pendingRequestCount"
  Data.Either.Right
    { mode
    , recordedMessageCount
    , activeInterceptCount
    , pendingRequestCount
    }

encodeSessionConfig :: SessionConfig -> Data.Argonaut.Core.Json
encodeSessionConfig config =
  "sessionId" := config.sessionId
    ~> "mode" := config.mode
    ~> "recordingPath" := config.recordingPath
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeSessionConfig :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError SessionConfig
decodeSessionConfig json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  sessionId <- obj .: "sessionId"
  mode <- obj .: "mode"
  recordingPath <- obj .:? "recordingPath"
  Data.Either.Right
    { sessionId
    , mode
    , recordingPath: Data.Maybe.fromMaybe Data.Maybe.Nothing recordingPath
    }
