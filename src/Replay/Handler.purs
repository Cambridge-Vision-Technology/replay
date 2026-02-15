module Replay.Handler
  ( handleCommand
  , handleEvent
  , handleControlCommand
  , HandleResult(..)
  , HandleError(..)
  , ControlResult(..)
  , PendingForwards
  , emptyPendingForwards
  , registerPendingForward
  , resolvePendingForward
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Int as Data.Int
import Data.Map as Data.Map
import Data.Maybe as Data.Maybe
import Data.Newtype as Data.Newtype
import Data.String as Data.String
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Now as Effect.Now
import Effect.Ref as Effect.Ref
import Foreign.Object as Foreign.Object
import Replay.Protocol.Envelope as Replay.Protocol.Envelope
import Replay.Interceptor as Replay.Interceptor
import Replay.Player as Replay.Player
import Replay.Recorder as Replay.Recorder
import Replay.Session as Replay.Session
import Replay.Types as Replay.Types
import Replay.Hash as Replay.Hash
import Replay.Recording as Replay.Recording
import Replay.Time as Replay.Time
import Replay.Protocol.Types as Replay.Protocol.Types
import Data.Tuple as Data.Tuple

type PendingForwards = Replay.Session.PendingForwards

emptyPendingForwards :: Effect.Effect PendingForwards
emptyPendingForwards = Replay.Session.emptyPendingForwards

registerPendingForward :: PendingForwards -> Replay.Protocol.Types.StreamId -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command -> Effect.Effect Unit
registerPendingForward = Replay.Session.registerPendingForward

resolvePendingForward :: PendingForwards -> Replay.Protocol.Types.StreamId -> Effect.Effect (Data.Maybe.Maybe (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command))
resolvePendingForward = Replay.Session.resolvePendingForward

data HandleError
  = UnexpectedCommand String
  | PlaybackError Replay.Types.HarnessError
  | UnexpectedChannel String
  | NoPendingForward Replay.Protocol.Types.StreamId

derive instance Eq HandleError

instance Show HandleError where
  show (UnexpectedCommand msg) = "UnexpectedCommand: " <> msg
  show (PlaybackError err) = "PlaybackError: " <> show err
  show (UnexpectedChannel msg) = "UnexpectedChannel: " <> msg
  show (NoPendingForward streamId) = "NoPendingForward: " <> show streamId

data HandleResult
  = RespondDirectly (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event)
  | ForwardToPlatform (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command)
  | ForwardToProgram (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event)
  | NoResponse

instance Show HandleResult where
  show (RespondDirectly env) = "RespondDirectly " <> show env
  show (ForwardToPlatform env) = "ForwardToPlatform " <> show env
  show (ForwardToProgram env) = "ForwardToProgram " <> show env
  show NoResponse = "NoResponse"

handleCommand
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> Data.Maybe.Maybe Replay.Player.PlayerState
  -> PendingForwards
  -> Replay.Interceptor.InterceptRegistry
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handleCommand mode maybeRecorder maybePlayer pendingForwards interceptRegistry commandEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = commandEnvelope
  case env.channel of
    Replay.Protocol.Types.ProgramChannel ->
      handleProgramChannelCommand mode maybeRecorder maybePlayer pendingForwards interceptRegistry commandEnvelope
    Replay.Protocol.Types.PlatformChannel ->
      pure $ Data.Either.Left (UnexpectedChannel "Received Command on PlatformChannel - expected Event")
    Replay.Protocol.Types.ControlChannel ->
      pure $ Data.Either.Left (UnexpectedChannel "Received Command on ControlChannel - use ControlEnvelope instead")

handleEvent
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> PendingForwards
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handleEvent mode maybeRecorder pendingForwards eventEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = eventEnvelope
  case env.channel of
    Replay.Protocol.Types.PlatformChannel ->
      handlePlatformChannelEvent mode maybeRecorder pendingForwards eventEnvelope
    Replay.Protocol.Types.ProgramChannel ->
      pure $ Data.Either.Left (UnexpectedChannel "Received Event on ProgramChannel - harness sends events, not receives")
    Replay.Protocol.Types.ControlChannel ->
      pure $ Data.Either.Left (UnexpectedChannel "Received Event on ControlChannel - use ControlResponse instead")

handleProgramChannelCommand
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> Data.Maybe.Maybe Replay.Player.PlayerState
  -> PendingForwards
  -> Replay.Interceptor.InterceptRegistry
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handleProgramChannelCommand mode maybeRecorder maybePlayer pendingForwards interceptRegistry commandEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = commandEnvelope
  case env.payload of
    Replay.Protocol.Types.CommandOpen requestPayload -> do
      interceptResult <- Effect.Class.liftEffect $ Replay.Interceptor.matchRequest requestPayload interceptRegistry
      case interceptResult of
        Data.Maybe.Just intercept ->
          handleInterceptMatch mode maybeRecorder commandEnvelope intercept
        Data.Maybe.Nothing ->
          handleProgramChannelCommandByMode mode maybeRecorder maybePlayer pendingForwards commandEnvelope
    Replay.Protocol.Types.CommandClose ->
      handleProgramChannelCommandByMode mode maybeRecorder maybePlayer pendingForwards commandEnvelope

handleInterceptMatch
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Replay.Interceptor.InterceptResult
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handleInterceptMatch _mode maybeRecorder commandEnvelope interceptResult = do
  let (Replay.Protocol.Types.Envelope env) = commandEnvelope
  case interceptResult.delay of
    Data.Maybe.Just (Replay.Protocol.Types.Milliseconds delayMs) ->
      Effect.Aff.delay (Effect.Aff.Milliseconds (Data.Int.toNumber delayMs))
    Data.Maybe.Nothing ->
      pure unit

  timestamp <- Effect.Class.liftEffect Replay.Time.getCurrentTimestamp

  let responseEnvelope = Replay.Protocol.Envelope.buildResponseEnvelope env timestamp interceptResult.response

  case maybeRecorder of
    Data.Maybe.Just recorder -> do
      Effect.Class.liftEffect $ recordCommandToRecorder recorder commandEnvelope
      Effect.Class.liftEffect $ recordEventToRecorder recorder responseEnvelope
    Data.Maybe.Nothing ->
      pure unit

  pure $ Data.Either.Right (RespondDirectly responseEnvelope)

handleProgramChannelCommandByMode
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> Data.Maybe.Maybe Replay.Player.PlayerState
  -> PendingForwards
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handleProgramChannelCommandByMode mode maybeRecorder maybePlayer pendingForwards commandEnvelope =
  case mode of
    Replay.Types.ModePassthrough ->
      handleProgramPassthrough pendingForwards commandEnvelope

    Replay.Types.ModeRecord ->
      handleProgramRecord maybeRecorder pendingForwards commandEnvelope

    Replay.Types.ModePlayback ->
      handleProgramPlayback maybeRecorder maybePlayer commandEnvelope

handlePlatformChannelEvent
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> PendingForwards
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handlePlatformChannelEvent mode maybeRecorder pendingForwards eventEnvelope =
  case mode of
    Replay.Types.ModePassthrough ->
      handlePlatformPassthrough pendingForwards eventEnvelope

    Replay.Types.ModeRecord ->
      handlePlatformRecord maybeRecorder pendingForwards eventEnvelope

    Replay.Types.ModePlayback ->
      pure $ Data.Either.Left (UnexpectedChannel "Received PlatformChannel event in playback mode")

handleProgramPassthrough
  :: PendingForwards
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handleProgramPassthrough pendingForwards commandEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = commandEnvelope
  case env.payload of
    Replay.Protocol.Types.CommandOpen _ -> do
      Effect.Class.liftEffect $ registerPendingForward pendingForwards env.streamId commandEnvelope
      let
        forwardedEnvelope = Replay.Protocol.Types.Envelope
          env { channel = Replay.Protocol.Types.PlatformChannel }
      pure $ Data.Either.Right (ForwardToPlatform forwardedEnvelope)

    Replay.Protocol.Types.CommandClose -> do
      timestamp <- Effect.Class.liftEffect Replay.Time.getCurrentTimestamp
      pure $ Data.Either.Right (RespondDirectly (Replay.Protocol.Envelope.buildResponseEnvelope env timestamp unexpectedClosePayload))

handlePlatformPassthrough
  :: PendingForwards
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handlePlatformPassthrough pendingForwards eventEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = eventEnvelope
  maybePending <- Effect.Class.liftEffect $ resolvePendingForward pendingForwards env.streamId
  case maybePending of
    Data.Maybe.Nothing ->
      pure $ Data.Either.Left (NoPendingForward env.streamId)
    Data.Maybe.Just _originalCommand -> do
      let
        forwardedEnvelope = Replay.Protocol.Types.Envelope
          env { channel = Replay.Protocol.Types.ProgramChannel }
      pure $ Data.Either.Right (ForwardToProgram forwardedEnvelope)

handleProgramRecord
  :: Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> PendingForwards
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handleProgramRecord maybeRecorder pendingForwards commandEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = commandEnvelope
  case env.payload of
    Replay.Protocol.Types.CommandOpen _ -> do
      case maybeRecorder of
        Data.Maybe.Just recorder ->
          Effect.Class.liftEffect $ recordCommandToRecorder recorder commandEnvelope
        Data.Maybe.Nothing ->
          pure unit

      Effect.Class.liftEffect $ registerPendingForward pendingForwards env.streamId commandEnvelope
      let
        forwardedEnvelope = Replay.Protocol.Types.Envelope
          env { channel = Replay.Protocol.Types.PlatformChannel }
      pure $ Data.Either.Right (ForwardToPlatform forwardedEnvelope)

    Replay.Protocol.Types.CommandClose -> do
      timestamp <- Effect.Class.liftEffect Replay.Time.getCurrentTimestamp
      pure $ Data.Either.Right (RespondDirectly (Replay.Protocol.Envelope.buildResponseEnvelope env timestamp unexpectedClosePayload))

handlePlatformRecord
  :: Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> PendingForwards
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handlePlatformRecord maybeRecorder pendingForwards eventEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = eventEnvelope
  maybePending <- Effect.Class.liftEffect $ resolvePendingForward pendingForwards env.streamId
  case maybePending of
    Data.Maybe.Nothing ->
      pure $ Data.Either.Left (NoPendingForward env.streamId)
    Data.Maybe.Just _originalCommand -> do
      let
        responseForRecording = Replay.Protocol.Types.Envelope
          env { channel = Replay.Protocol.Types.ProgramChannel }
      case maybeRecorder of
        Data.Maybe.Just recorder ->
          Effect.Class.liftEffect $ recordEventToRecorder recorder responseForRecording
        Data.Maybe.Nothing ->
          pure unit

      let
        forwardedEnvelope = Replay.Protocol.Types.Envelope
          env { channel = Replay.Protocol.Types.ProgramChannel }
      pure $ Data.Either.Right (ForwardToProgram forwardedEnvelope)

handleProgramPlayback
  :: Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> Data.Maybe.Maybe Replay.Player.PlayerState
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Aff.Aff (Data.Either.Either HandleError HandleResult)
handleProgramPlayback maybeRecorder maybePlayer commandEnvelope =
  case maybePlayer of
    Data.Maybe.Nothing ->
      pure $ Data.Either.Left (UnexpectedCommand "Playback mode requires PlayerState")
    Data.Maybe.Just player -> do
      result <- Replay.Player.playbackRequest commandEnvelope player
      case result of
        Data.Either.Left err ->
          pure $ Data.Either.Left (PlaybackError (playerErrorToHarnessError err))
        Data.Either.Right eventEnvelope -> do
          case maybeRecorder of
            Data.Maybe.Just recorder -> do
              Effect.Class.liftEffect $ recordCommandToRecorder recorder commandEnvelope
              Effect.Class.liftEffect $ recordEventToRecorder recorder eventEnvelope
            Data.Maybe.Nothing ->
              pure unit
          pure $ Data.Either.Right (RespondDirectly eventEnvelope)

playerErrorToHarnessError :: Replay.Player.PlaybackError -> Replay.Types.HarnessError
playerErrorToHarnessError = case _ of
  Replay.Player.NoMatchFound payload ->
    Replay.Types.PlaybackNoMatch ("{service: " <> payload.service <> ", payload: " <> Data.Argonaut.Core.stringify payload.payload <> "}")
  Replay.Player.AllMatchesUsed payload ->
    Replay.Types.PlaybackAllUsed ("{service: " <> payload.service <> ", payload: " <> Data.Argonaut.Core.stringify payload.payload <> "}")
  Replay.Player.InvalidRequest msg ->
    Replay.Types.HarnessInternalError ("InvalidRequest: " <> msg)
  Replay.Player.UnexpectedPayload msg ->
    Replay.Types.HarnessInternalError ("UnexpectedPayload: " <> msg)

unexpectedClosePayload :: Replay.Protocol.Types.ResponsePayload
unexpectedClosePayload =
  { service: "error"
  , payload: Data.Argonaut.Core.fromObject $ Foreign.Object.fromFoldable
      [ Data.Tuple.Tuple "errorType" (Data.Argonaut.Core.fromString "unexpected_close")
      , Data.Tuple.Tuple "message" (Data.Argonaut.Core.fromString "Received close command without open")
      ]
  }

recordCommandToRecorder
  :: Replay.Recorder.RecorderState
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Effect Unit
recordCommandToRecorder recorder commandEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = commandEnvelope
  now <- Effect.Now.now
  let recordedAt = Replay.Time.formatTimestamp now
  let
    payloadEnvelope = Replay.Protocol.Types.Envelope
      { streamId: env.streamId
      , traceId: env.traceId
      , causationStreamId: env.causationStreamId
      , parentStreamId: env.parentStreamId
      , siblingIndex: env.siblingIndex
      , eventSeq: env.eventSeq
      , timestamp: env.timestamp
      , channel: env.channel
      , payloadHash: env.payloadHash
      , payload: Replay.Recording.PayloadCommand env.payload
      }
  maybeHash <- case env.payloadHash of
    Data.Maybe.Just clientHash ->
      pure $ Data.Maybe.Just clientHash
    Data.Maybe.Nothing ->
      case env.payload of
        Replay.Protocol.Types.CommandOpen requestPayload -> do
          (Replay.Hash.PayloadHash h) <- Replay.Hash.computePayloadHash requestPayload
          pure $ Data.Maybe.Just h
        Replay.Protocol.Types.CommandClose ->
          pure Data.Maybe.Nothing
  let
    message =
      { envelope: payloadEnvelope
      , recordedAt
      , direction: Replay.Recording.ToHarness
      , hash: maybeHash
      }
  Replay.Recorder.recordMessage recorder message

recordEventToRecorder
  :: Replay.Recorder.RecorderState
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event
  -> Effect.Effect Unit
recordEventToRecorder recorder eventEnvelope = do
  let (Replay.Protocol.Types.Envelope env) = eventEnvelope
  now <- Effect.Now.now
  let recordedAt = Replay.Time.formatTimestamp now
  let
    payloadEnvelope = Replay.Protocol.Types.Envelope
      { streamId: env.streamId
      , traceId: env.traceId
      , causationStreamId: env.causationStreamId
      , parentStreamId: env.parentStreamId
      , siblingIndex: env.siblingIndex
      , eventSeq: env.eventSeq
      , timestamp: env.timestamp
      , channel: env.channel
      , payloadHash: env.payloadHash
      , payload: Replay.Recording.PayloadEvent env.payload
      }
  let
    message =
      { envelope: payloadEnvelope
      , recordedAt
      , direction: Replay.Recording.FromHarness
      , hash: Data.Maybe.Nothing
      }
  Replay.Recorder.recordMessage recorder message

data ControlResult
  = ControlSuccess Replay.Protocol.Types.ControlResponse
  | ControlFailure Replay.Protocol.Types.ControlErrorType

derive instance Eq ControlResult

instance Show ControlResult where
  show (ControlSuccess resp) = "ControlSuccess " <> show resp
  show (ControlFailure err) = "ControlFailure " <> show err

handleControlCommand
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> PendingForwards
  -> Replay.Interceptor.InterceptRegistry
  -> Replay.Session.SessionRegistry
  -> Replay.Protocol.Types.ControlCommand
  -> Effect.Aff.Aff ControlResult
handleControlCommand mode maybeRecorder pendingForwards interceptRegistry sessionRegistry command =
  case command of
    Replay.Protocol.Types.GetMessages filter ->
      handleGetMessages maybeRecorder filter

    Replay.Protocol.Types.GetMessageCount filter ->
      handleGetMessageCount maybeRecorder filter

    Replay.Protocol.Types.GetStatus ->
      handleGetStatus mode maybeRecorder pendingForwards interceptRegistry

    Replay.Protocol.Types.RegisterIntercept spec ->
      handleRegisterIntercept interceptRegistry spec

    Replay.Protocol.Types.RemoveIntercept interceptId ->
      handleRemoveIntercept interceptRegistry interceptId

    Replay.Protocol.Types.ClearIntercepts maybeService ->
      handleClearIntercepts interceptRegistry maybeService

    Replay.Protocol.Types.ListIntercepts ->
      handleListIntercepts interceptRegistry

    Replay.Protocol.Types.GetInterceptStats interceptId ->
      handleGetInterceptStats interceptRegistry interceptId

    Replay.Protocol.Types.CreateSession config ->
      handleCreateSession sessionRegistry config

    Replay.Protocol.Types.CloseSession sessionId ->
      handleCloseSession sessionRegistry sessionId

    Replay.Protocol.Types.ListSessions ->
      handleListSessions sessionRegistry

handleGetMessages
  :: Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> Replay.Protocol.Types.MessageFilter
  -> Effect.Aff.Aff ControlResult
handleGetMessages maybeRecorder filter =
  case maybeRecorder of
    Data.Maybe.Nothing ->
      pure $ ControlSuccess (Replay.Protocol.Types.MessagesResult [])
    Data.Maybe.Just recorder -> do
      messages <- Effect.Class.liftEffect $ Replay.Recorder.getMessages recorder
      let filtered = filterMessages filter messages
      let jsonMessages = map (Data.Argonaut.Encode.encodeJson <<< _.envelope) filtered
      pure $ ControlSuccess (Replay.Protocol.Types.MessagesResult jsonMessages)

handleGetMessageCount
  :: Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> Replay.Protocol.Types.MessageFilter
  -> Effect.Aff.Aff ControlResult
handleGetMessageCount maybeRecorder filter =
  case maybeRecorder of
    Data.Maybe.Nothing ->
      pure $ ControlSuccess (Replay.Protocol.Types.CountResult 0)
    Data.Maybe.Just recorder -> do
      messages <- Effect.Class.liftEffect $ Replay.Recorder.getMessages recorder
      let filtered = filterMessages filter messages
      pure $ ControlSuccess (Replay.Protocol.Types.CountResult (Data.Array.length filtered))

handleGetStatus
  :: Replay.Types.HarnessMode
  -> Data.Maybe.Maybe Replay.Recorder.RecorderState
  -> PendingForwards
  -> Replay.Interceptor.InterceptRegistry
  -> Effect.Aff.Aff ControlResult
handleGetStatus mode maybeRecorder pendingForwards interceptRegistry = do
  messageCount <- case maybeRecorder of
    Data.Maybe.Nothing ->
      pure 0
    Data.Maybe.Just recorder -> do
      messages <- Effect.Class.liftEffect $ Replay.Recorder.getMessages recorder
      pure $ Data.Array.length messages

  pendingCount <- Effect.Class.liftEffect do
    forwards <- Effect.Ref.read pendingForwards.forwardsRef
    pure $ Data.Map.size forwards

  activeInterceptCount <- Effect.Class.liftEffect $ Replay.Interceptor.getActiveCount interceptRegistry

  let
    status =
      { mode
      , recordedMessageCount: messageCount
      , activeInterceptCount
      , pendingRequestCount: pendingCount
      }

  pure $ ControlSuccess (Replay.Protocol.Types.StatusResult status)

handleRegisterIntercept
  :: Replay.Interceptor.InterceptRegistry
  -> Replay.Protocol.Types.InterceptSpec
  -> Effect.Aff.Aff ControlResult
handleRegisterIntercept interceptRegistry spec = do
  interceptId <- Effect.Class.liftEffect $ Replay.Interceptor.register spec interceptRegistry
  pure $ ControlSuccess (Replay.Protocol.Types.InterceptRegistered interceptId)

handleRemoveIntercept
  :: Replay.Interceptor.InterceptRegistry
  -> Replay.Protocol.Types.InterceptId
  -> Effect.Aff.Aff ControlResult
handleRemoveIntercept interceptRegistry interceptId = do
  success <- Effect.Class.liftEffect $ Replay.Interceptor.remove interceptId interceptRegistry
  pure $ ControlSuccess (Replay.Protocol.Types.InterceptRemoved success)

handleClearIntercepts
  :: Replay.Interceptor.InterceptRegistry
  -> Data.Maybe.Maybe String
  -> Effect.Aff.Aff ControlResult
handleClearIntercepts interceptRegistry maybeService = do
  count <- Effect.Class.liftEffect $ Replay.Interceptor.clear maybeService interceptRegistry
  pure $ ControlSuccess (Replay.Protocol.Types.InterceptsCleared count)

handleListIntercepts
  :: Replay.Interceptor.InterceptRegistry
  -> Effect.Aff.Aff ControlResult
handleListIntercepts interceptRegistry = do
  entries <- Effect.Class.liftEffect $ Replay.Interceptor.listAll interceptRegistry
  let interceptInfos = map entryToInterceptInfo entries
  pure $ ControlSuccess (Replay.Protocol.Types.InterceptList interceptInfos)
  where
  entryToInterceptInfo :: Replay.Interceptor.InterceptEntry -> Replay.Protocol.Types.InterceptInfo
  entryToInterceptInfo entry =
    { interceptId: entry.interceptId
    , spec: entry.spec
    , matchCount: entry.matchCount
    , remainingMatches: entry.remainingMatches
    }

handleGetInterceptStats
  :: Replay.Interceptor.InterceptRegistry
  -> Replay.Protocol.Types.InterceptId
  -> Effect.Aff.Aff ControlResult
handleGetInterceptStats interceptRegistry interceptId = do
  maybeStats <- Effect.Class.liftEffect $ Replay.Interceptor.getStats interceptId interceptRegistry
  case maybeStats of
    Data.Maybe.Nothing ->
      pure $ ControlFailure (Replay.Protocol.Types.InternalError ("Intercept not found: " <> show interceptId))
    Data.Maybe.Just stats ->
      pure $ ControlSuccess (Replay.Protocol.Types.InterceptStatsResult { matchCount: stats.matchCount })

handleCreateSession
  :: Replay.Session.SessionRegistry
  -> Replay.Protocol.Types.SessionConfig
  -> Effect.Aff.Aff ControlResult
handleCreateSession sessionRegistry config = do
  result <- Replay.Session.createSession config sessionRegistry
  case result of
    Data.Either.Left err ->
      pure $ ControlSuccess (Replay.Protocol.Types.SessionError err)
    Data.Either.Right session ->
      pure $ ControlSuccess (Replay.Protocol.Types.SessionCreated session.sessionId)

handleCloseSession
  :: Replay.Session.SessionRegistry
  -> Replay.Protocol.Types.SessionId
  -> Effect.Aff.Aff ControlResult
handleCloseSession sessionRegistry sessionId = do
  result <- Replay.Session.closeSession sessionId sessionRegistry
  case result of
    Data.Either.Left err ->
      pure $ ControlSuccess (Replay.Protocol.Types.SessionError err)
    Data.Either.Right _ ->
      pure $ ControlSuccess (Replay.Protocol.Types.SessionClosed sessionId)

handleListSessions
  :: Replay.Session.SessionRegistry
  -> Effect.Aff.Aff ControlResult
handleListSessions sessionRegistry = do
  sessions <- Effect.Class.liftEffect $ Replay.Session.listSessions sessionRegistry
  pure $ ControlSuccess (Replay.Protocol.Types.SessionList sessions)

filterMessages
  :: Replay.Protocol.Types.MessageFilter
  -> Array Replay.Recording.RecordedMessage
  -> Array Replay.Recording.RecordedMessage
filterMessages filter messages =
  Data.Array.filter (messageMatchesFilter filter) messages

messageMatchesFilter
  :: Replay.Protocol.Types.MessageFilter
  -> Replay.Recording.RecordedMessage
  -> Boolean
messageMatchesFilter filter message =
  matchesService filter.service message
    && matchesDirection filter.direction message
    && matchesFunctionName filter.functionName message
    && matchesUrlMatch filter.urlMatch message
    && matchesMethod filter.method message
    && matchesPayloadContains filter.payloadContains message

matchesService
  :: Data.Maybe.Maybe String
  -> Replay.Recording.RecordedMessage
  -> Boolean
matchesService Data.Maybe.Nothing _ = true
matchesService (Data.Maybe.Just serviceType) message =
  case getMessageServiceType message of
    Data.Maybe.Nothing -> false
    Data.Maybe.Just msgService -> msgService == serviceType

matchesDirection
  :: Data.Maybe.Maybe Replay.Protocol.Types.MessageDirection
  -> Replay.Recording.RecordedMessage
  -> Boolean
matchesDirection Data.Maybe.Nothing _ = true
matchesDirection (Data.Maybe.Just direction) message =
  message.direction == direction

matchesFunctionName
  :: Data.Maybe.Maybe String
  -> Replay.Recording.RecordedMessage
  -> Boolean
matchesFunctionName Data.Maybe.Nothing _ = true
matchesFunctionName (Data.Maybe.Just fnName) message =
  case getMessageFunctionName message of
    Data.Maybe.Nothing -> false
    Data.Maybe.Just msgFnName -> msgFnName == fnName

matchesUrlMatch
  :: Data.Maybe.Maybe Replay.Protocol.Types.UrlMatch
  -> Replay.Recording.RecordedMessage
  -> Boolean
matchesUrlMatch Data.Maybe.Nothing _ = true
matchesUrlMatch (Data.Maybe.Just urlMatch) message =
  case getMessageUrl message of
    Data.Maybe.Nothing -> false
    Data.Maybe.Just msgUrl ->
      case urlMatch of
        Replay.Protocol.Types.UrlExact exact -> msgUrl == exact
        Replay.Protocol.Types.UrlContains substr ->
          Data.String.contains (Data.String.Pattern substr) msgUrl

matchesMethod
  :: Data.Maybe.Maybe String
  -> Replay.Recording.RecordedMessage
  -> Boolean
matchesMethod Data.Maybe.Nothing _ = true
matchesMethod (Data.Maybe.Just method) message =
  case getMessageMethod message of
    Data.Maybe.Nothing -> false
    Data.Maybe.Just msgMethod -> msgMethod == method

matchesPayloadContains
  :: Data.Maybe.Maybe String
  -> Replay.Recording.RecordedMessage
  -> Boolean
matchesPayloadContains Data.Maybe.Nothing _ = true
matchesPayloadContains (Data.Maybe.Just searchStr) message =
  let
    payloadJson = Data.Argonaut.Encode.encodeJson message.envelope
    payloadStr = Data.Argonaut.Core.stringify payloadJson
  in
    Data.String.contains (Data.String.Pattern searchStr) payloadStr

getMessageServiceType
  :: Replay.Recording.RecordedMessage
  -> Data.Maybe.Maybe String
getMessageServiceType message =
  let
    (Replay.Protocol.Types.Envelope env) = message.envelope
  in
    case env.payload of
      Replay.Recording.PayloadCommand cmd ->
        case cmd of
          Replay.Protocol.Types.CommandOpen requestPayload ->
            Data.Maybe.Just requestPayload.service
          Replay.Protocol.Types.CommandClose ->
            Data.Maybe.Nothing
      Replay.Recording.PayloadEvent evt ->
        case evt of
          Replay.Protocol.Types.EventClose responsePayload ->
            Data.Maybe.Just responsePayload.service
          Replay.Protocol.Types.EventData _ ->
            Data.Maybe.Nothing

getMessageFunctionName
  :: Replay.Recording.RecordedMessage
  -> Data.Maybe.Maybe String
getMessageFunctionName message =
  let
    (Replay.Protocol.Types.Envelope env) = message.envelope
  in
    case env.payload of
      Replay.Recording.PayloadCommand cmd ->
        case cmd of
          Replay.Protocol.Types.CommandOpen requestPayload ->
            getJsonField "functionName" requestPayload.payload
          _ ->
            Data.Maybe.Nothing
      _ ->
        Data.Maybe.Nothing

getMessageUrl
  :: Replay.Recording.RecordedMessage
  -> Data.Maybe.Maybe String
getMessageUrl message =
  let
    (Replay.Protocol.Types.Envelope env) = message.envelope
  in
    case env.payload of
      Replay.Recording.PayloadCommand cmd ->
        case cmd of
          Replay.Protocol.Types.CommandOpen requestPayload ->
            getJsonField "url" requestPayload.payload
          _ ->
            Data.Maybe.Nothing
      _ ->
        Data.Maybe.Nothing

getMessageMethod
  :: Replay.Recording.RecordedMessage
  -> Data.Maybe.Maybe String
getMessageMethod message =
  let
    (Replay.Protocol.Types.Envelope env) = message.envelope
  in
    case env.payload of
      Replay.Recording.PayloadCommand cmd ->
        case cmd of
          Replay.Protocol.Types.CommandOpen requestPayload ->
            getJsonField "method" requestPayload.payload
          _ ->
            Data.Maybe.Nothing
      _ ->
        Data.Maybe.Nothing

getJsonField :: String -> Data.Argonaut.Core.Json -> Data.Maybe.Maybe String
getJsonField fieldName json =
  case Data.Argonaut.Core.toObject json of
    Data.Maybe.Nothing -> Data.Maybe.Nothing
    Data.Maybe.Just obj ->
      case Foreign.Object.lookup fieldName obj of
        Data.Maybe.Nothing -> Data.Maybe.Nothing
        Data.Maybe.Just value ->
          Data.Argonaut.Core.toString value
