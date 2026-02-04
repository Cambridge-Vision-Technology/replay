module Replay.Server
  ( startServer
  , startServerOnSocket
  , stopServer
  , onMessage
  , sendMessage
  , sendMessageSafe
  , getConnectionQuery
  , getConnectionId
  , module Replay.Types
  , startHarnessServer
  , HarnessServer
  , ConnectionSessions
  ) where

import Prelude

import Data.Array as Data.Array
import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Either as Data.Either
import Data.Map as Data.Map
import Data.Maybe as Data.Maybe
import Data.Nullable as Data.Nullable
import Data.String as Data.String
import Data.Tuple as Data.Tuple
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Console as Effect.Console
import Effect.Exception as Effect.Exception
import Effect.Ref as Effect.Ref
import Effect.Uncurried as Effect.Uncurried
import Foreign.Object as Foreign.Object
import Replay.Handler as Replay.Handler
import Replay.Interceptor as Replay.Interceptor
import Replay.Player as Replay.Player
import Replay.Protocol.Types as Replay.Protocol.Types
import Replay.Recorder as Replay.Recorder
import Replay.Session as Replay.Session
import Replay.Types as Replay.Types

foreign import createServerImpl
  :: Effect.Uncurried.EffectFn3
       Int
       (Replay.Types.WebSocketConnection -> Effect.Effect Unit)
       (String -> Effect.Effect Unit)
       Replay.Types.WebSocketServer

foreign import createServerOnSocketImpl
  :: Effect.Uncurried.EffectFn4
       String
       (Replay.Types.WebSocketConnection -> Effect.Effect Unit)
       (Replay.Types.WebSocketServer -> Effect.Effect Unit)
       (String -> Effect.Effect Unit)
       Replay.Types.WebSocketServer

foreign import closeServerImpl
  :: Effect.Uncurried.EffectFn1 Replay.Types.WebSocketServer Unit

foreign import onMessageImpl
  :: Effect.Uncurried.EffectFn2
       Replay.Types.WebSocketConnection
       (String -> Effect.Effect Unit)
       Unit

foreign import onCloseImpl
  :: Effect.Uncurried.EffectFn2
       Replay.Types.WebSocketConnection
       (Effect.Effect Unit)
       Unit

foreign import sendSafeImpl
  :: Effect.Uncurried.EffectFn2
       Replay.Types.WebSocketConnection
       String
       { success :: Boolean, error :: Data.Nullable.Nullable String }

foreign import getConnectionIdImpl
  :: Effect.Uncurried.EffectFn1 Replay.Types.WebSocketConnection String

foreign import getConnectionUrlImpl
  :: Effect.Uncurried.EffectFn1 Replay.Types.WebSocketConnection (Data.Nullable.Nullable String)

startServer
  :: Int
  -> (Replay.Types.WebSocketConnection -> Effect.Effect Unit)
  -> Effect.Aff.Aff (Data.Either.Either Replay.Types.WebSocketError Replay.Types.WebSocketServer)
startServer port onConnection = Effect.Aff.makeAff \callback -> do
  let
    handleError :: String -> Effect.Effect Unit
    handleError errMsg = callback (Data.Either.Right (Data.Either.Left (Replay.Types.ServerStartFailed errMsg)))
  server <- Effect.Uncurried.runEffectFn3 createServerImpl port onConnection handleError
  callback (Data.Either.Right (Data.Either.Right server))
  pure Effect.Aff.nonCanceler

startServerOnSocket
  :: String
  -> (Replay.Types.WebSocketConnection -> Effect.Effect Unit)
  -> Effect.Aff.Aff (Data.Either.Either Replay.Types.WebSocketError Replay.Types.WebSocketServer)
startServerOnSocket socketPath onConnection = Effect.Aff.makeAff \callback -> do
  let
    handleReady :: Replay.Types.WebSocketServer -> Effect.Effect Unit
    handleReady server = callback (Data.Either.Right (Data.Either.Right server))

    handleError :: String -> Effect.Effect Unit
    handleError errMsg = callback (Data.Either.Right (Data.Either.Left (Replay.Types.ServerStartFailed errMsg)))
  _ <- Effect.Uncurried.runEffectFn4 createServerOnSocketImpl socketPath onConnection handleReady handleError
  pure Effect.Aff.nonCanceler

stopServer :: Replay.Types.WebSocketServer -> Effect.Aff.Aff Unit
stopServer server = Effect.Class.liftEffect (Effect.Uncurried.runEffectFn1 closeServerImpl server)

onMessage
  :: Replay.Types.WebSocketConnection
  -> (String -> Effect.Effect Unit)
  -> Effect.Effect Unit
onMessage conn callback = Effect.Uncurried.runEffectFn2 onMessageImpl conn callback

onClose
  :: Replay.Types.WebSocketConnection
  -> Effect.Effect Unit
  -> Effect.Effect Unit
onClose conn callback = Effect.Uncurried.runEffectFn2 onCloseImpl conn callback

sendMessage
  :: Replay.Types.WebSocketConnection
  -> String
  -> Effect.Effect Unit
sendMessage conn msg = do
  result <- sendMessageSafe conn msg
  case result of
    Data.Either.Left err ->
      Effect.Console.error $ "WebSocket send failed: " <> err
    Data.Either.Right _ ->
      pure unit

sendMessageSafe
  :: Replay.Types.WebSocketConnection
  -> String
  -> Effect.Effect (Data.Either.Either String Unit)
sendMessageSafe conn msg = do
  result <- Effect.Uncurried.runEffectFn2 sendSafeImpl conn msg
  pure $
    if result.success then Data.Either.Right unit
    else Data.Either.Left (Data.Maybe.fromMaybe "Unknown error" (Data.Nullable.toMaybe result.error))

getConnectionQuery :: Replay.Types.WebSocketConnection -> Effect.Effect (Foreign.Object.Object String)
getConnectionQuery conn = do
  maybeUrl <- Data.Nullable.toMaybe <$> Effect.Uncurried.runEffectFn1 getConnectionUrlImpl conn
  pure $ case maybeUrl of
    Data.Maybe.Nothing -> Foreign.Object.empty
    Data.Maybe.Just url -> parseQueryString url

parseQueryString :: String -> Foreign.Object.Object String
parseQueryString url =
  case Data.String.indexOf (Data.String.Pattern "?") url of
    Data.Maybe.Nothing ->
      Foreign.Object.empty
    Data.Maybe.Just idx ->
      let
        queryPart = Data.String.drop (idx + 1) url
        pairs = Data.String.split (Data.String.Pattern "&") queryPart
      in
        Foreign.Object.fromFoldable $ Data.Array.mapMaybe parseParam pairs
  where
  parseParam :: String -> Data.Maybe.Maybe (Data.Tuple.Tuple String String)
  parseParam param =
    case Data.String.indexOf (Data.String.Pattern "=") param of
      Data.Maybe.Nothing ->
        Data.Maybe.Nothing
      Data.Maybe.Just eqIdx ->
        let
          key = Data.String.take eqIdx param
          value = Data.String.drop (eqIdx + 1) param
        in
          Data.Maybe.Just (Data.Tuple.Tuple key value)

type ConnectionSessions = Effect.Ref.Ref (Data.Map.Map Replay.Types.ConnectionId Replay.Protocol.Types.SessionId)

type HarnessServer =
  { server :: Replay.Types.WebSocketServer
  , mode :: Replay.Types.HarnessMode
  , baseRecordingDir :: Data.Maybe.Maybe String
  , recorder :: Data.Maybe.Maybe Replay.Recorder.RecorderState
  , player :: Data.Maybe.Maybe Replay.Player.PlayerState
  , pendingForwards :: Replay.Handler.PendingForwards
  , interceptRegistry :: Replay.Interceptor.InterceptRegistry
  , sessionRegistry :: Replay.Session.SessionRegistry
  , connectionSessions :: ConnectionSessions
  }

startHarnessServer
  :: Replay.Types.HarnessConfig
  -> Data.Maybe.Maybe Replay.Player.PlayerState
  -> Effect.Aff.Aff (Data.Either.Either Replay.Types.WebSocketError HarnessServer)
startHarnessServer config maybePlayer = do
  maybeRecorder <- case config.mode of
    Replay.Types.ModeRecord -> do
      recorder <- Effect.Class.liftEffect $ Replay.Recorder.createRecorder (Data.Maybe.fromMaybe "unnamed" config.recordingPath)
      pure $ Data.Maybe.Just recorder
    _ ->
      pure Data.Maybe.Nothing

  pendingForwards <- Effect.Class.liftEffect Replay.Handler.emptyPendingForwards
  interceptRegistry <- Effect.Class.liftEffect Replay.Interceptor.newRegistry
  sessionRegistry <- Effect.Class.liftEffect Replay.Session.newRegistry
  connectionSessions <- Effect.Class.liftEffect $ Effect.Ref.new Data.Map.empty

  let
    serverState =
      { mode: config.mode
      , baseRecordingDir: config.baseRecordingDir
      , recorder: maybeRecorder
      , player: maybePlayer
      , pendingForwards
      , interceptRegistry
      , sessionRegistry
      , connectionSessions
      }

  let connectionHandler = handleConnection serverState

  serverResult <- case config.listenTarget of
    Replay.Types.ListenOnPort port ->
      startServer port connectionHandler
    Replay.Types.ListenOnSocket socketPath ->
      startServerOnSocket socketPath connectionHandler

  case serverResult of
    Data.Either.Left err ->
      pure $ Data.Either.Left err
    Data.Either.Right server ->
      pure $ Data.Either.Right
        { server
        , mode: config.mode
        , baseRecordingDir: config.baseRecordingDir
        , recorder: maybeRecorder
        , player: maybePlayer
        , pendingForwards
        , interceptRegistry
        , sessionRegistry
        , connectionSessions
        }

type ServerState =
  { mode :: Replay.Types.HarnessMode
  , baseRecordingDir :: Data.Maybe.Maybe String
  , recorder :: Data.Maybe.Maybe Replay.Recorder.RecorderState
  , player :: Data.Maybe.Maybe Replay.Player.PlayerState
  , pendingForwards :: Replay.Handler.PendingForwards
  , interceptRegistry :: Replay.Interceptor.InterceptRegistry
  , sessionRegistry :: Replay.Session.SessionRegistry
  , connectionSessions :: ConnectionSessions
  }

getConnectionId :: Replay.Types.WebSocketConnection -> Effect.Effect Replay.Types.ConnectionId
getConnectionId conn = do
  idStr <- Effect.Uncurried.runEffectFn1 getConnectionIdImpl conn
  pure (Replay.Types.ConnectionId idStr)

handleConnection
  :: ServerState
  -> Replay.Types.WebSocketConnection
  -> Effect.Effect Unit
handleConnection serverState conn = do
  queryParams <- getConnectionQuery conn
  let maybeSessionParam = Foreign.Object.lookup "session" queryParams
  connId <- getConnectionId conn

  case maybeSessionParam of
    Data.Maybe.Just sessionIdStr -> do
      let sessionId = Replay.Protocol.Types.SessionId sessionIdStr
      Effect.Ref.modify_ (Data.Map.insert connId sessionId) serverState.connectionSessions

      onMessage conn \msgStr -> do
        Effect.Aff.runAff_ (handleMessageError conn) do
          handleSessionMessage serverState sessionId conn msgStr

      onClose conn do
        Effect.Ref.modify_ (Data.Map.delete connId) serverState.connectionSessions

    Data.Maybe.Nothing -> do
      onMessage conn \msgStr -> do
        Effect.Aff.runAff_ (handleMessageError conn) do
          handleIncomingMessage
            serverState.mode
            serverState.recorder
            serverState.player
            serverState.pendingForwards
            serverState.interceptRegistry
            serverState.sessionRegistry
            conn
            msgStr

handleMessageError
  :: Replay.Types.WebSocketConnection
  -> Data.Either.Either Effect.Exception.Error Unit
  -> Effect.Effect Unit
handleMessageError _ (Data.Either.Right _) = pure unit
handleMessageError conn (Data.Either.Left err) = do
  let errorMsg = Effect.Exception.message err
  Effect.Console.error $ "Harness message handler error: " <> errorMsg
  sendMessage conn (makeErrorResponse ("Internal harness error: " <> errorMsg))

handleSessionMessage
  :: ServerState
  -> Replay.Protocol.Types.SessionId
  -> Replay.Types.WebSocketConnection
  -> String
  -> Effect.Aff.Aff Unit
handleSessionMessage serverState sessionId conn msgStr = do
  maybeSession <- Effect.Class.liftEffect $ Replay.Session.getSession sessionId serverState.sessionRegistry

  case maybeSession of
    Data.Maybe.Nothing ->
      Effect.Class.liftEffect $ sendMessage conn (makeErrorResponse ("session not found: " <> show sessionId))

    Data.Maybe.Just session ->
      handleIncomingMessageWithSession serverState session conn msgStr

handleIncomingMessageWithSession
  :: ServerState
  -> Replay.Session.SessionState
  -> Replay.Types.WebSocketConnection
  -> String
  -> Effect.Aff.Aff Unit
handleIncomingMessageWithSession serverState session conn msgStr = do
  case Data.Argonaut.Decode.parseJson msgStr of
    Data.Either.Left _ ->
      Effect.Class.liftEffect $ sendMessage conn (makeErrorResponse "Invalid JSON")
    Data.Either.Right json ->
      case decodeControlEnvelope json of
        Data.Either.Right controlEnv -> do
          result <- Replay.Handler.handleControlCommand
            session.mode
            session.recorder
            session.pendingForwards
            session.interceptRegistry
            serverState.sessionRegistry
            controlEnv.payload
          Effect.Class.liftEffect $ sendMessage conn (encodeControlResponse controlEnv.requestId result)

        Data.Either.Left _controlDecodeErr ->
          case Data.Argonaut.Decode.decodeJson json of
            Data.Either.Right (commandEnvelope :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command) -> do
              result <- Replay.Handler.handleCommand
                session.mode
                session.recorder
                session.player
                session.pendingForwards
                session.interceptRegistry
                commandEnvelope
              processHandleResult conn (Data.Maybe.Just commandEnvelope) result

            Data.Either.Left _commandDecodeErr ->
              case Data.Argonaut.Decode.decodeJson json of
                Data.Either.Right (eventEnvelope :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event) -> do
                  result <- Replay.Handler.handleEvent
                    session.mode
                    session.recorder
                    session.pendingForwards
                    eventEnvelope
                  processHandleResult conn Data.Maybe.Nothing result

                Data.Either.Left eventDecodeErr ->
                  Effect.Class.liftEffect $ sendMessage conn (makeErrorResponse ("Failed to decode message: " <> Data.Argonaut.Decode.printJsonDecodeError eventDecodeErr))

handleIncomingMessage
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> Data.Maybe.Maybe Replay.Player.PlayerState
  -> Replay.Handler.PendingForwards
  -> Replay.Interceptor.InterceptRegistry
  -> Replay.Session.SessionRegistry
  -> Replay.Types.WebSocketConnection
  -> String
  -> Effect.Aff.Aff Unit
handleIncomingMessage mode maybeRecorder maybePlayer pendingForwards interceptRegistry sessionRegistry conn msgStr = do
  case Data.Argonaut.Decode.parseJson msgStr of
    Data.Either.Left _ ->
      Effect.Class.liftEffect $ sendMessage conn (makeErrorResponse "Invalid JSON")
    Data.Either.Right json ->
      case decodeControlEnvelope json of
        Data.Either.Right controlEnv -> do
          result <- Replay.Handler.handleControlCommand mode maybeRecorder pendingForwards interceptRegistry sessionRegistry controlEnv.payload
          Effect.Class.liftEffect $ sendMessage conn (encodeControlResponse controlEnv.requestId result)

        Data.Either.Left _controlDecodeErr ->
          case Data.Argonaut.Decode.decodeJson json of
            Data.Either.Right (commandEnvelope :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command) -> do
              result <- Replay.Handler.handleCommand mode maybeRecorder maybePlayer pendingForwards interceptRegistry commandEnvelope
              processHandleResult conn (Data.Maybe.Just commandEnvelope) result

            Data.Either.Left _commandDecodeErr ->
              case Data.Argonaut.Decode.decodeJson json of
                Data.Either.Right (eventEnvelope :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event) -> do
                  result <- Replay.Handler.handleEvent mode maybeRecorder pendingForwards eventEnvelope
                  processHandleResult conn Data.Maybe.Nothing result

                Data.Either.Left eventDecodeErr ->
                  Effect.Class.liftEffect $ sendMessage conn (makeErrorResponse ("Failed to decode message: " <> Data.Argonaut.Decode.printJsonDecodeError eventDecodeErr))

processHandleResult
  :: Replay.Types.WebSocketConnection
  -> Data.Maybe.Maybe (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command)
  -> Data.Either.Either Replay.Handler.HandleError Replay.Handler.HandleResult
  -> Effect.Aff.Aff Unit
processHandleResult conn maybeOriginalCommand result =
  case result of
    Data.Either.Left handleErr ->
      case maybeOriginalCommand of
        Data.Maybe.Just commandEnvelope ->
          Effect.Class.liftEffect $ sendMessage conn (makeEnvelopedErrorResponse commandEnvelope (show handleErr))
        Data.Maybe.Nothing ->
          Effect.Class.liftEffect $ sendMessage conn (makeErrorResponse (show handleErr))

    Data.Either.Right handleResult ->
      case handleResult of
        Replay.Handler.RespondDirectly eventEnvelope ->
          Effect.Class.liftEffect $ sendMessage conn (Data.Argonaut.Core.stringify (Data.Argonaut.Encode.encodeJson eventEnvelope))

        Replay.Handler.ForwardToPlatform commandEnvelope ->
          Effect.Class.liftEffect $ sendMessage conn (Data.Argonaut.Core.stringify (Data.Argonaut.Encode.encodeJson commandEnvelope))

        Replay.Handler.ForwardToProgram eventEnvelope ->
          Effect.Class.liftEffect $ sendMessage conn (Data.Argonaut.Core.stringify (Data.Argonaut.Encode.encodeJson eventEnvelope))

        Replay.Handler.NoResponse ->
          Effect.Class.liftEffect do
            Effect.Console.error "Warning: Handler returned NoResponse - sending acknowledgment to prevent client timeout"
            sendMessage conn (makeAckResponse)

makeErrorResponse :: String -> String
makeErrorResponse msg =
  Data.Argonaut.Core.stringify
    ( Data.Argonaut.Encode.encodeJson
        { error: msg
        }
    )

makeAckResponse :: String
makeAckResponse =
  Data.Argonaut.Core.stringify
    ( Data.Argonaut.Encode.encodeJson
        { ack: true
        , warning: "Handler returned NoResponse - this may indicate a protocol issue"
        }
    )

makeEnvelopedErrorResponse :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command -> String -> String
makeEnvelopedErrorResponse (Replay.Protocol.Types.Envelope env) errorMsg =
  let
    errorPayload :: Replay.Protocol.Types.ResponsePayload
    errorPayload =
      { service: "error"
      , payload: Data.Argonaut.Core.fromObject $ Foreign.Object.fromFoldable
          [ Data.Tuple.Tuple "errorType" (Data.Argonaut.Core.fromString "HarnessError")
          , Data.Tuple.Tuple "message" (Data.Argonaut.Core.fromString errorMsg)
          ]
      }
    eventEnvelope = Replay.Protocol.Types.Envelope
      { streamId: env.streamId
      , traceId: env.traceId
      , causationStreamId: env.causationStreamId
      , parentStreamId: env.parentStreamId
      , siblingIndex: env.siblingIndex
      , eventSeq: Replay.Protocol.Types.EventSeq 1
      , timestamp: env.timestamp
      , channel: env.channel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.EventClose errorPayload
      }
  in
    Data.Argonaut.Core.stringify (Data.Argonaut.Encode.encodeJson eventEnvelope)

decodeControlEnvelope
  :: Data.Argonaut.Core.Json
  -> Data.Either.Either Data.Argonaut.Decode.JsonDecodeError Replay.Protocol.Types.ControlEnvelope
decodeControlEnvelope json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  requestId <- Data.Argonaut.Decode.getField obj "requestId"
  payload <- Data.Argonaut.Decode.getField obj "payload"
  pure { requestId, payload }

encodeControlResponse
  :: Replay.Protocol.Types.RequestId
  -> Replay.Handler.ControlResult
  -> String
encodeControlResponse requestId result =
  let
    response = case result of
      Replay.Handler.ControlSuccess controlResponse ->
        Data.Argonaut.Encode.encodeJson
          { requestId: requestId
          , success: true
          , payload: controlResponse
          }
      Replay.Handler.ControlFailure errorType ->
        Data.Argonaut.Encode.encodeJson
          { requestId: requestId
          , success: false
          , error: errorType
          }
  in
    Data.Argonaut.Core.stringify response
