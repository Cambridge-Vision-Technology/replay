module Replay.Session
  ( SessionState
  , SessionRegistry
  , PendingForwards
  , newRegistry
  , createSession
  , getSession
  , closeSession
  , listSessions
  , emptyPendingForwards
  , registerPendingForward
  , resolvePendingForward
  ) where

import Prelude

import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Map as Data.Map
import Data.Maybe as Data.Maybe
import Data.Tuple as Data.Tuple
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Ref as Effect.Ref
import Replay.Interceptor as Replay.Interceptor
import Replay.Player as Replay.Player
import Replay.Protocol.Types as Replay.Protocol.Types
import Replay.Recorder as Replay.Recorder
import Replay.Recording as Replay.Recording
import Replay.Types as Replay.Types

type PendingForwards =
  { forwardsRef :: Effect.Ref.Ref (Data.Map.Map Replay.Protocol.Types.StreamId (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command))
  }

type SessionState =
  { sessionId :: Replay.Protocol.Types.SessionId
  , mode :: Replay.Types.HarnessMode
  , recordingPath :: Data.Maybe.Maybe String
  , recorder :: Data.Maybe.Maybe Replay.Recorder.RecorderState
  , player :: Data.Maybe.Maybe Replay.Player.PlayerState
  , pendingForwards :: PendingForwards
  , interceptRegistry :: Replay.Interceptor.InterceptRegistry
  }

type SessionRegistry =
  { sessionsRef :: Effect.Ref.Ref (Data.Map.Map Replay.Protocol.Types.SessionId SessionState)
  }

emptyPendingForwards :: Effect.Effect PendingForwards
emptyPendingForwards = do
  forwardsRef <- Effect.Ref.new Data.Map.empty
  pure { forwardsRef }

registerPendingForward
  :: PendingForwards
  -> Replay.Protocol.Types.StreamId
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Effect.Effect Unit
registerPendingForward pending streamId commandEnvelope =
  Effect.Ref.modify_ (Data.Map.insert streamId commandEnvelope) pending.forwardsRef

resolvePendingForward
  :: PendingForwards
  -> Replay.Protocol.Types.StreamId
  -> Effect.Effect (Data.Maybe.Maybe (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command))
resolvePendingForward pending streamId = do
  forwards <- Effect.Ref.read pending.forwardsRef
  let result = Data.Map.lookup streamId forwards
  Effect.Ref.modify_ (Data.Map.delete streamId) pending.forwardsRef
  pure result

newRegistry :: Effect.Effect SessionRegistry
newRegistry = do
  sessionsRef <- Effect.Ref.new Data.Map.empty
  pure { sessionsRef }

createSession
  :: Replay.Protocol.Types.SessionConfig
  -> SessionRegistry
  -> Effect.Aff.Aff (Data.Either.Either Replay.Protocol.Types.SessionError SessionState)
createSession config registry = do
  sessions <- Effect.Class.liftEffect $ Effect.Ref.read registry.sessionsRef
  if Data.Map.member config.sessionId sessions then
    pure $ Data.Either.Left (Replay.Protocol.Types.SessionAlreadyExists config.sessionId)
  else do
    pendingForwards <- Effect.Class.liftEffect emptyPendingForwards
    interceptRegistry <- Effect.Class.liftEffect Replay.Interceptor.newRegistry

    recorderPlayerResult <- createRecorderAndPlayer config

    case recorderPlayerResult of
      Data.Either.Left err ->
        pure $ Data.Either.Left err
      Data.Either.Right { recorder, player } -> do
        let
          sessionState =
            { sessionId: config.sessionId
            , mode: config.mode
            , recordingPath: config.recordingPath
            , recorder
            , player
            , pendingForwards
            , interceptRegistry
            }

        Effect.Class.liftEffect $ Effect.Ref.modify_
          (Data.Map.insert config.sessionId sessionState)
          registry.sessionsRef

        pure $ Data.Either.Right sessionState

createRecorderAndPlayer
  :: Replay.Protocol.Types.SessionConfig
  -> Effect.Aff.Aff
       ( Data.Either.Either
           Replay.Protocol.Types.SessionError
           { recorder :: Data.Maybe.Maybe Replay.Recorder.RecorderState
           , player :: Data.Maybe.Maybe Replay.Player.PlayerState
           }
       )
createRecorderAndPlayer config =
  case config.mode of
    Replay.Types.ModeRecord -> do
      let scenarioName = Data.Maybe.fromMaybe (unwrapSessionId config.sessionId) config.recordingPath
      recorder <- Effect.Class.liftEffect $ Replay.Recorder.createRecorder scenarioName
      pure $ Data.Either.Right
        { recorder: Data.Maybe.Just recorder
        , player: Data.Maybe.Nothing
        }

    Replay.Types.ModePlayback -> do
      case config.recordingPath of
        Data.Maybe.Nothing ->
          pure $ Data.Either.Right
            { recorder: Data.Maybe.Nothing
            , player: Data.Maybe.Nothing
            }
        Data.Maybe.Just path -> do
          loadResult <- Replay.Recording.loadRecording path
          case loadResult of
            Data.Either.Left err ->
              pure $ Data.Either.Left (Replay.Protocol.Types.RecordingLoadFailed err)
            Data.Either.Right recording -> do
              player <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording
              pure $ Data.Either.Right
                { recorder: Data.Maybe.Nothing
                , player: Data.Maybe.Just player
                }

    Replay.Types.ModePassthrough ->
      pure $ Data.Either.Right
        { recorder: Data.Maybe.Nothing
        , player: Data.Maybe.Nothing
        }

getSession
  :: Replay.Protocol.Types.SessionId
  -> SessionRegistry
  -> Effect.Effect (Data.Maybe.Maybe SessionState)
getSession sessionId registry = do
  sessions <- Effect.Ref.read registry.sessionsRef
  pure $ Data.Map.lookup sessionId sessions

closeSession
  :: Replay.Protocol.Types.SessionId
  -> SessionRegistry
  -> Effect.Aff.Aff (Data.Either.Either Replay.Protocol.Types.SessionError Unit)
closeSession sessionId registry = do
  maybeSession <- Effect.Class.liftEffect do
    sessions <- Effect.Ref.read registry.sessionsRef
    case Data.Map.lookup sessionId sessions of
      Data.Maybe.Nothing ->
        pure Data.Maybe.Nothing
      Data.Maybe.Just session -> do
        Effect.Ref.modify_ (Data.Map.delete sessionId) registry.sessionsRef
        pure $ Data.Maybe.Just session

  case maybeSession of
    Data.Maybe.Nothing ->
      pure $ Data.Either.Left (Replay.Protocol.Types.SessionNotFound sessionId)
    Data.Maybe.Just session -> do
      case session.mode, session.recorder, session.recordingPath of
        Replay.Types.ModeRecord, Data.Maybe.Just recorder, Data.Maybe.Just path -> do
          _ <- Replay.Recorder.saveRecording recorder path
          pure $ Data.Either.Right unit
        _, _, _ ->
          pure $ Data.Either.Right unit

listSessions :: SessionRegistry -> Effect.Effect (Array Replay.Protocol.Types.SessionId)
listSessions registry = do
  sessions <- Effect.Ref.read registry.sessionsRef
  let entries = Data.Map.toUnfoldable sessions :: Array (Data.Tuple.Tuple Replay.Protocol.Types.SessionId SessionState)
  pure $ map Data.Tuple.fst entries

unwrapSessionId :: Replay.Protocol.Types.SessionId -> String
unwrapSessionId (Replay.Protocol.Types.SessionId s) = s
