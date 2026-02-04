module Replay.Types
  ( HarnessMode(..)
  , HarnessConfig
  , ListenTarget(..)
  , WebSocketServer
  , WebSocketConnection
  , ConnectionId(..)
  , WebSocketError(..)
  , ReadyState(..)
  , HarnessError(..)
  ) where

import Prelude

import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Decode (class DecodeJson, (.:))
import Data.Argonaut.Decode.Error as Data.Argonaut.Decode.Error
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Argonaut.Encode (class EncodeJson, (:=), (~>))
import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Either as Data.Either
import Data.Generic.Rep as Data.Generic.Rep
import Data.Maybe as Data.Maybe
import Data.Newtype as Data.Newtype
import Data.Show.Generic as Data.Show.Generic

data HarnessMode
  = ModePassthrough
  | ModeRecord
  | ModePlayback

derive instance Eq HarnessMode
derive instance Ord HarnessMode

instance Show HarnessMode where
  show ModePassthrough = "ModePassthrough"
  show ModeRecord = "ModeRecord"
  show ModePlayback = "ModePlayback"

instance EncodeJson HarnessMode where
  encodeJson ModePassthrough = Data.Argonaut.Encode.encodeJson "passthrough"
  encodeJson ModeRecord = Data.Argonaut.Encode.encodeJson "record"
  encodeJson ModePlayback = Data.Argonaut.Encode.encodeJson "playback"

instance DecodeJson HarnessMode where
  decodeJson json = do
    str <- Data.Argonaut.Decode.decodeJson json
    case str of
      "passthrough" -> Data.Either.Right ModePassthrough
      "record" -> Data.Either.Right ModeRecord
      "playback" -> Data.Either.Right ModePlayback
      other -> Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown harness mode: " <> other))

data ListenTarget
  = ListenOnPort Int
  | ListenOnSocket String

derive instance Eq ListenTarget

instance Show ListenTarget where
  show (ListenOnPort port) = "ListenOnPort " <> show port
  show (ListenOnSocket path) = "ListenOnSocket " <> path

type HarnessConfig =
  { listenTarget :: ListenTarget
  , mode :: HarnessMode
  , recordingPath :: Data.Maybe.Maybe String
  , baseRecordingDir :: Data.Maybe.Maybe String
  }

newtype ConnectionId = ConnectionId String

derive instance Data.Newtype.Newtype ConnectionId _
derive instance Eq ConnectionId
derive instance Ord ConnectionId
derive newtype instance Show ConnectionId

instance EncodeJson ConnectionId where
  encodeJson (ConnectionId s) = Data.Argonaut.Encode.encodeJson s

instance DecodeJson ConnectionId where
  decodeJson json = ConnectionId <$> Data.Argonaut.Decode.decodeJson json

foreign import data WebSocketServer :: Type

foreign import data WebSocketConnection :: Type

data WebSocketError
  = ConnectionFailed String
  | MessageSendFailed String
  | ServerStartFailed String
  | ConnectionClosed

derive instance Eq WebSocketError

instance Show WebSocketError where
  show (ConnectionFailed msg) = "ConnectionFailed: " <> msg
  show (MessageSendFailed msg) = "MessageSendFailed: " <> msg
  show (ServerStartFailed msg) = "ServerStartFailed: " <> msg
  show ConnectionClosed = "ConnectionClosed"

instance EncodeJson WebSocketError where
  encodeJson (ConnectionFailed msg) =
    "type" := ("connection_failed" :: String)
      ~> "message" := msg
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (MessageSendFailed msg) =
    "type" := ("message_send_failed" :: String)
      ~> "message" := msg
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (ServerStartFailed msg) =
    "type" := ("server_start_failed" :: String)
      ~> "message" := msg
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson ConnectionClosed =
    "type" := ("connection_closed" :: String)
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson WebSocketError where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    errorType :: String <- obj .: "type"
    case errorType of
      "connection_failed" -> do
        message <- obj .: "message"
        Data.Either.Right (ConnectionFailed message)
      "message_send_failed" -> do
        message <- obj .: "message"
        Data.Either.Right (MessageSendFailed message)
      "server_start_failed" -> do
        message <- obj .: "message"
        Data.Either.Right (ServerStartFailed message)
      "connection_closed" ->
        Data.Either.Right ConnectionClosed
      other ->
        Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown error type: " <> other))

data ReadyState
  = Connecting
  | Open
  | Closing
  | Closed

derive instance Eq ReadyState

instance Show ReadyState where
  show Connecting = "Connecting"
  show Open = "Open"
  show Closing = "Closing"
  show Closed = "Closed"

data HarnessError
  = SessionNotFoundError String
  | SessionAlreadyExistsError String
  | PlaybackNoMatch String
  | PlaybackAllUsed String
  | RecordingLoadError String
  | RecordingSaveError String
  | WebSocketSendError String
  | HarnessInternalError String

derive instance Eq HarnessError
derive instance Data.Generic.Rep.Generic HarnessError _

instance Show HarnessError where
  show = Data.Show.Generic.genericShow

instance EncodeJson HarnessError where
  encodeJson (SessionNotFoundError sessionId) =
    "type" := ("session_not_found" :: String)
      ~> "sessionId" := sessionId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (SessionAlreadyExistsError sessionId) =
    "type" := ("session_already_exists" :: String)
      ~> "sessionId" := sessionId
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (PlaybackNoMatch details) =
    "type" := ("playback_no_match" :: String)
      ~> "details" := details
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (PlaybackAllUsed details) =
    "type" := ("playback_all_used" :: String)
      ~> "details" := details
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (RecordingLoadError reason) =
    "type" := ("recording_load_failed" :: String)
      ~> "reason" := reason
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (RecordingSaveError reason) =
    "type" := ("recording_save_failed" :: String)
      ~> "reason" := reason
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (WebSocketSendError reason) =
    "type" := ("websocket_send_failed" :: String)
      ~> "reason" := reason
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (HarnessInternalError reason) =
    "type" := ("harness_internal_error" :: String)
      ~> "reason" := reason
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson HarnessError where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    errorType :: String <- obj .: "type"
    case errorType of
      "session_not_found" -> do
        sessionId <- obj .: "sessionId"
        Data.Either.Right (SessionNotFoundError sessionId)
      "session_already_exists" -> do
        sessionId <- obj .: "sessionId"
        Data.Either.Right (SessionAlreadyExistsError sessionId)
      "playback_no_match" -> do
        details <- obj .: "details"
        Data.Either.Right (PlaybackNoMatch details)
      "playback_all_used" -> do
        details <- obj .: "details"
        Data.Either.Right (PlaybackAllUsed details)
      "recording_load_failed" -> do
        reason <- obj .: "reason"
        Data.Either.Right (RecordingLoadError reason)
      "recording_save_failed" -> do
        reason <- obj .: "reason"
        Data.Either.Right (RecordingSaveError reason)
      "websocket_send_failed" -> do
        reason <- obj .: "reason"
        Data.Either.Right (WebSocketSendError reason)
      "harness_internal_error" -> do
        reason <- obj .: "reason"
        Data.Either.Right (HarnessInternalError reason)
      other ->
        Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown harness error type: " <> other))
