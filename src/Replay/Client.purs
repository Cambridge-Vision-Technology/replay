module Replay.Client
  ( connect
  , connectToSocket
  , connectToSocketWithSession
  , disconnect
  , sendCommand
  , sendEvent
  , onMessage
  , module Replay.Types
  , ChannelHandlers
  , setupMessageHandler
  , parseIncomingMessage
  , IncomingMessage(..)
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Either as Data.Either
import Data.Maybe as Data.Maybe
import Data.Newtype as Data.Newtype
import Effect as Effect
import Foreign.Object as Foreign.Object
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Uncurried as Effect.Uncurried
import Replay.Types as Replay.Types
import Replay.Protocol.Types as Replay.Protocol.Types

foreign import connectImpl
  :: Effect.Uncurried.EffectFn3
       String
       (Replay.Types.WebSocketConnection -> Effect.Effect Unit)
       (String -> Effect.Effect Unit)
       Replay.Types.WebSocketConnection

foreign import connectToSocketImpl
  :: Effect.Uncurried.EffectFn3
       String
       (Replay.Types.WebSocketConnection -> Effect.Effect Unit)
       (String -> Effect.Effect Unit)
       Replay.Types.WebSocketConnection

foreign import connectToSocketWithSessionImpl
  :: Effect.Uncurried.EffectFn4
       String
       String
       (Replay.Types.WebSocketConnection -> Effect.Effect Unit)
       (String -> Effect.Effect Unit)
       Replay.Types.WebSocketConnection

foreign import disconnectImpl
  :: Effect.Uncurried.EffectFn1 Replay.Types.WebSocketConnection Unit

foreign import sendImpl
  :: Effect.Uncurried.EffectFn2
       Replay.Types.WebSocketConnection
       String
       Unit

foreign import onMessageImpl
  :: Effect.Uncurried.EffectFn2
       Replay.Types.WebSocketConnection
       (String -> Effect.Effect Unit)
       Unit

connect
  :: String
  -> Effect.Aff.Aff (Data.Either.Either Replay.Types.WebSocketError Replay.Types.WebSocketConnection)
connect url = Effect.Aff.makeAff \callback -> do
  let
    handleOpen :: Replay.Types.WebSocketConnection -> Effect.Effect Unit
    handleOpen conn = callback (Data.Either.Right (Data.Either.Right conn))

    handleError :: String -> Effect.Effect Unit
    handleError errMsg = callback (Data.Either.Right (Data.Either.Left (Replay.Types.ConnectionFailed errMsg)))

  _ <- Effect.Uncurried.runEffectFn3 connectImpl url handleOpen handleError
  pure Effect.Aff.nonCanceler

connectToSocket
  :: String
  -> Effect.Aff.Aff (Data.Either.Either Replay.Types.WebSocketError Replay.Types.WebSocketConnection)
connectToSocket socketPath = Effect.Aff.makeAff \callback -> do
  let
    handleOpen :: Replay.Types.WebSocketConnection -> Effect.Effect Unit
    handleOpen conn = callback (Data.Either.Right (Data.Either.Right conn))

    handleError :: String -> Effect.Effect Unit
    handleError errMsg = callback (Data.Either.Right (Data.Either.Left (Replay.Types.ConnectionFailed errMsg)))

  _ <- Effect.Uncurried.runEffectFn3 connectToSocketImpl socketPath handleOpen handleError
  pure Effect.Aff.nonCanceler

connectToSocketWithSession
  :: String
  -> Replay.Protocol.Types.SessionId
  -> Effect.Aff.Aff (Data.Either.Either Replay.Types.WebSocketError Replay.Types.WebSocketConnection)
connectToSocketWithSession socketPath sessionId = Effect.Aff.makeAff \callback -> do
  let
    handleOpen :: Replay.Types.WebSocketConnection -> Effect.Effect Unit
    handleOpen conn = callback (Data.Either.Right (Data.Either.Right conn))

    handleError :: String -> Effect.Effect Unit
    handleError errMsg = callback (Data.Either.Right (Data.Either.Left (Replay.Types.ConnectionFailed errMsg)))

    sessionIdStr = Data.Newtype.unwrap sessionId

  _ <- Effect.Uncurried.runEffectFn4 connectToSocketWithSessionImpl socketPath sessionIdStr handleOpen handleError
  pure Effect.Aff.nonCanceler

disconnect :: Replay.Types.WebSocketConnection -> Effect.Aff.Aff Unit
disconnect conn = Effect.Class.liftEffect (Effect.Uncurried.runEffectFn1 disconnectImpl conn)

sendCommand
  :: Replay.Types.WebSocketConnection
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Effect Unit
sendCommand conn envelope = do
  let json = Data.Argonaut.Encode.encodeJson envelope
  let str = Data.Argonaut.Core.stringify json
  Effect.Uncurried.runEffectFn2 sendImpl conn str

onMessage
  :: Replay.Types.WebSocketConnection
  -> (String -> Effect.Effect Unit)
  -> Effect.Effect Unit
onMessage conn callback = Effect.Uncurried.runEffectFn2 onMessageImpl conn callback

-- ============================================================================
-- Bidirectional Message Handling
-- ============================================================================

type ChannelHandlers =
  { onProgramCommand :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command -> Effect.Effect Unit
  , onProgramEvent :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event -> Effect.Effect Unit
  , onPlatformCommand :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command -> Effect.Effect Unit
  , onPlatformEvent :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event -> Effect.Effect Unit
  , onParseError :: String -> Effect.Effect Unit
  }

data IncomingMessage
  = IncomingProgramCommand (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command)
  | IncomingProgramEvent (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event)
  | IncomingPlatformCommand (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command)
  | IncomingPlatformEvent (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event)
  | ParseError String

instance Show IncomingMessage where
  show (IncomingProgramCommand env) = "IncomingProgramCommand " <> show env
  show (IncomingProgramEvent env) = "IncomingProgramEvent " <> show env
  show (IncomingPlatformCommand env) = "IncomingPlatformCommand " <> show env
  show (IncomingPlatformEvent env) = "IncomingPlatformEvent " <> show env
  show (ParseError err) = "ParseError: " <> err

parseIncomingMessage :: String -> IncomingMessage
parseIncomingMessage msg =
  case Data.Argonaut.Decode.parseJson msg of
    Data.Either.Left parseErr ->
      ParseError ("JSON parse error: " <> Data.Argonaut.Decode.printJsonDecodeError parseErr)
    Data.Either.Right json ->
      case extractChannelAndType json of
        Data.Either.Left err ->
          ParseError err
        Data.Either.Right { channel, isCommand } ->
          case channel of
            Replay.Protocol.Types.ProgramChannel ->
              if isCommand then
                case Data.Argonaut.Decode.decodeJson json of
                  Data.Either.Left decodeErr ->
                    ParseError ("Decode error (program command): " <> Data.Argonaut.Decode.printJsonDecodeError decodeErr)
                  Data.Either.Right envelope ->
                    IncomingProgramCommand envelope
              else
                case Data.Argonaut.Decode.decodeJson json of
                  Data.Either.Left decodeErr ->
                    ParseError ("Decode error (program event): " <> Data.Argonaut.Decode.printJsonDecodeError decodeErr)
                  Data.Either.Right envelope ->
                    IncomingProgramEvent envelope
            Replay.Protocol.Types.PlatformChannel ->
              if isCommand then
                case Data.Argonaut.Decode.decodeJson json of
                  Data.Either.Left decodeErr ->
                    ParseError ("Decode error (platform command): " <> Data.Argonaut.Decode.printJsonDecodeError decodeErr)
                  Data.Either.Right envelope ->
                    IncomingPlatformCommand envelope
              else
                case Data.Argonaut.Decode.decodeJson json of
                  Data.Either.Left decodeErr ->
                    ParseError ("Decode error (platform event): " <> Data.Argonaut.Decode.printJsonDecodeError decodeErr)
                  Data.Either.Right envelope ->
                    IncomingPlatformEvent envelope
            Replay.Protocol.Types.ControlChannel ->
              -- Control channel messages use ControlEnvelope format, not regular Envelope
              -- This needs to be parsed separately - parseControlMessage handles this
              ParseError "Control channel messages should use parseControlMessage"

extractChannelAndType
  :: Data.Argonaut.Core.Json
  -> Data.Either.Either String { channel :: Replay.Protocol.Types.Channel, isCommand :: Boolean }
extractChannelAndType json =
  case Data.Argonaut.Core.toObject json of
    Data.Maybe.Nothing ->
      Data.Either.Left "Message is not a JSON object"
    Data.Maybe.Just obj -> do
      case Foreign.Object.lookup "channel" obj of
        Data.Maybe.Nothing ->
          Data.Either.Left "Missing 'channel' field"
        Data.Maybe.Just channelJson ->
          case Data.Argonaut.Decode.decodeJson channelJson of
            Data.Either.Left decodeErr ->
              Data.Either.Left ("Invalid channel: " <> Data.Argonaut.Decode.printJsonDecodeError decodeErr)
            Data.Either.Right channel -> do
              case Foreign.Object.lookup "payload" obj of
                Data.Maybe.Nothing ->
                  Data.Either.Left "Missing 'payload' field"
                Data.Maybe.Just payloadJson ->
                  case Data.Argonaut.Core.toObject payloadJson of
                    Data.Maybe.Nothing ->
                      Data.Either.Left "Payload is not a JSON object"
                    Data.Maybe.Just payloadObj ->
                      case Foreign.Object.lookup "type" payloadObj of
                        Data.Maybe.Nothing ->
                          Data.Either.Left "Missing 'type' field in payload"
                        Data.Maybe.Just typeJson ->
                          case Data.Argonaut.Core.toString typeJson of
                            Data.Maybe.Nothing ->
                              Data.Either.Left "Type is not a string"
                            Data.Maybe.Just typeStr ->
                              -- Determine if message is a command or event:
                              -- - "open" is always a command (CommandOpen)
                              -- - "data" is always an event (EventData)
                              -- - "close" could be either CommandClose or EventClose
                              --   CommandClose has no inner payload, EventClose has payload
                              let
                                -- Determine if this is a Command or Event based on type
                                -- CommandClose has no payload field, EventClose has payload
                                isCommand = case typeStr of
                                  "open" ->
                                    true
                                  "data" ->
                                    false
                                  "close" ->
                                    not (Foreign.Object.member "payload" payloadObj)
                                  _ ->
                                    false
                              in
                                Data.Either.Right { channel, isCommand }

setupMessageHandler
  :: Replay.Types.WebSocketConnection
  -> ChannelHandlers
  -> Effect.Effect Unit
setupMessageHandler conn handlers =
  onMessage conn \msg -> do
    case parseIncomingMessage msg of
      IncomingProgramCommand envelope ->
        handlers.onProgramCommand envelope
      IncomingProgramEvent envelope ->
        handlers.onProgramEvent envelope
      IncomingPlatformCommand envelope ->
        handlers.onPlatformCommand envelope
      IncomingPlatformEvent envelope ->
        handlers.onPlatformEvent envelope
      ParseError err ->
        handlers.onParseError err

sendEvent
  :: Replay.Types.WebSocketConnection
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event
  -> Effect.Effect Unit
sendEvent conn envelope = do
  let json = Data.Argonaut.Encode.encodeJson envelope
  let str = Data.Argonaut.Core.stringify json
  Effect.Uncurried.runEffectFn2 sendImpl conn str
