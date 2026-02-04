module Replay.Recorder
  ( RecorderState
  , createRecorder
  , recordMessage
  , getMessages
  , saveRecording
  , getScenarioName
  ) where

import Prelude

import Data.Array as Data.Array
import Data.Either as Data.Either
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Ref as Effect.Ref
import Replay.Recording as Replay.Recording
import Replay.Time as Replay.Time

type RecorderState =
  { messagesRef :: Effect.Ref.Ref (Array Replay.Recording.RecordedMessage)
  , scenarioName :: String
  , startTimestamp :: String
  }

createRecorder :: String -> Effect.Effect RecorderState
createRecorder scenarioName = do
  messagesRef <- Effect.Ref.new []
  startTimestamp <- Replay.Time.getCurrentTimestamp
  pure { messagesRef, scenarioName, startTimestamp }

recordMessage :: RecorderState -> Replay.Recording.RecordedMessage -> Effect.Effect Unit
recordMessage state message =
  Effect.Ref.modify_ (\msgs -> Data.Array.snoc msgs message) state.messagesRef

getMessages :: RecorderState -> Effect.Effect (Array Replay.Recording.RecordedMessage)
getMessages state = Effect.Ref.read state.messagesRef

getScenarioName :: RecorderState -> String
getScenarioName state = state.scenarioName

saveRecording :: RecorderState -> String -> Effect.Aff.Aff (Data.Either.Either String Unit)
saveRecording state filepath = do
  messages <- Effect.Class.liftEffect $ Effect.Ref.read state.messagesRef
  let recording = buildRecording state messages
  Replay.Recording.saveRecording filepath recording

buildRecording :: RecorderState -> Array Replay.Recording.RecordedMessage -> Replay.Recording.Recording
buildRecording state messages =
  { schemaVersion: Replay.Recording.currentSchemaVersion
  , scenarioName: state.scenarioName
  , recordedAt: state.startTimestamp
  , messages
  }
