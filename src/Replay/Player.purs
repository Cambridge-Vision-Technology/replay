module Replay.Player
  ( PlayerState
  , PlaybackError(..)
  , createPlayerState
  , findMatch
  , findMatchWithHash
  , playbackRequest
  , markMessageUsed
  , getTranslationMap
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Foldable as Data.Foldable
import Data.Map as Data.Map
import Data.Maybe as Data.Maybe
import Data.Set as Data.Set
import Data.Tuple as Data.Tuple
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Ref as Effect.Ref
import Replay.Hash as Replay.Hash
import Replay.IdTranslation as Replay.IdTranslation
import Replay.Protocol.Types as Replay.Protocol.Types
import Replay.Recording as Replay.Recording

type PlayerState =
  { recording :: Replay.Recording.Recording
  , hashIndex :: Replay.Recording.HashIndex
  , usedMessagesRef :: Effect.Ref.Ref (Data.Set.Set Int)
  , translationMapRef :: Effect.Ref.Ref Replay.IdTranslation.TranslationMap
  }

data PlaybackError
  = NoMatchFound Replay.Protocol.Types.RequestPayload
  | AllMatchesUsed Replay.Protocol.Types.RequestPayload
  | InvalidRequest String
  | UnexpectedPayload String

instance Show PlaybackError where
  show (NoMatchFound payload) = "NoMatchFound: No recorded message matches request {service: " <> payload.service <> ", payload: " <> Data.Argonaut.Core.stringify payload.payload <> "}"
  show (AllMatchesUsed payload) = "AllMatchesUsed: All matching recorded messages have been used for {service: " <> payload.service <> ", payload: " <> Data.Argonaut.Core.stringify payload.payload <> "}"
  show (InvalidRequest msg) = "InvalidRequest: " <> msg
  show (UnexpectedPayload msg) = "UnexpectedPayload: " <> msg

createPlayerState :: Replay.Recording.Recording -> Effect.Effect PlayerState
createPlayerState recording = do
  let hashIndex = Replay.Recording.buildHashIndex recording
  usedMessagesRef <- Effect.Ref.new Data.Set.empty
  translationMapRef <- Effect.Ref.new Replay.IdTranslation.emptyTranslationMap
  pure { recording, hashIndex, usedMessagesRef, translationMapRef }

getTranslationMap :: PlayerState -> Effect.Effect Replay.IdTranslation.TranslationMap
getTranslationMap state = Effect.Ref.read state.translationMapRef

markMessageUsed :: PlayerState -> Int -> Effect.Effect Unit
markMessageUsed state index =
  Effect.Ref.modify_ (Data.Set.insert index) state.usedMessagesRef

findMatch
  :: Replay.Protocol.Types.RequestPayload
  -> PlayerState
  -> Effect.Effect (Data.Maybe.Maybe (Data.Tuple.Tuple Int Replay.Recording.RecordedMessage))
findMatch requestPayload state = do
  payloadHash <- Replay.Hash.computePayloadHash requestPayload
  findMatchWithHash (Replay.Hash.hashLookupKey payloadHash) state

findMatchWithHash
  :: String
  -> PlayerState
  -> Effect.Effect (Data.Maybe.Maybe (Data.Tuple.Tuple Int Replay.Recording.RecordedMessage))
findMatchWithHash hashKey state = do
  usedMessages <- Effect.Ref.read state.usedMessagesRef

  case Data.Map.lookup hashKey state.hashIndex of
    Data.Maybe.Just entries ->
      pure $ findFirstUnused usedMessages entries
    Data.Maybe.Nothing ->
      pure $ findMatchLinear hashKey usedMessages state.recording.messages
  where
  findFirstUnused :: Data.Set.Set Int -> Array { index :: Int, message :: Replay.Recording.RecordedMessage } -> Data.Maybe.Maybe (Data.Tuple.Tuple Int Replay.Recording.RecordedMessage)
  findFirstUnused usedSet entries =
    Data.Foldable.find (\entry -> not (Data.Set.member entry.index usedSet)) entries
      <#> \entry -> Data.Tuple.Tuple entry.index entry.message

findMatchLinear
  :: String
  -> Data.Set.Set Int
  -> Array Replay.Recording.RecordedMessage
  -> Data.Maybe.Maybe (Data.Tuple.Tuple Int Replay.Recording.RecordedMessage)
findMatchLinear hashKey usedMessages messages =
  let
    indexedMessages = Data.Array.mapWithIndex Data.Tuple.Tuple messages
    matchesRequest (Data.Tuple.Tuple index msg) =
      not (Data.Set.member index usedMessages)
        && msg.direction == Replay.Protocol.Types.ToHarness
        && msg.hash == Data.Maybe.Just hashKey
  in
    Data.Foldable.find matchesRequest indexedMessages

findCorrespondingResponse
  :: Int
  -> Replay.Protocol.Types.StreamId
  -> Array Replay.Recording.RecordedMessage
  -> Data.Maybe.Maybe Replay.Recording.RecordedMessage
findCorrespondingResponse commandIndex commandStreamId messages =
  let
    messagesAfterCommand = Data.Array.drop (commandIndex + 1) messages
  in
    Data.Foldable.find (isResponseForStream commandStreamId) messagesAfterCommand

isResponseForStream
  :: Replay.Protocol.Types.StreamId
  -> Replay.Recording.RecordedMessage
  -> Boolean
isResponseForStream streamId msg =
  msg.direction == Replay.Protocol.Types.FromHarness
    && getEnvelopeStreamId msg.envelope == streamId

getEnvelopeStreamId :: Replay.Protocol.Types.Envelope Replay.Recording.MessagePayload -> Replay.Protocol.Types.StreamId
getEnvelopeStreamId (Replay.Protocol.Types.Envelope env) = env.streamId

playbackRequest
  :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> PlayerState
  -> Effect.Aff.Aff (Data.Either.Either PlaybackError (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event))
playbackRequest commandEnvelope state = do
  let (Replay.Protocol.Types.Envelope env) = commandEnvelope
  case env.payload of
    Replay.Protocol.Types.CommandOpen requestPayload -> do
      matchResult <- Effect.Class.liftEffect $ case env.payloadHash of
        Data.Maybe.Just clientHash ->
          findMatchWithHash clientHash state
        Data.Maybe.Nothing ->
          findMatch requestPayload state
      case matchResult of
        Data.Maybe.Nothing ->
          pure $ Data.Either.Left (NoMatchFound requestPayload)

        Data.Maybe.Just (Data.Tuple.Tuple matchIndex matchedCommand) -> do
          let (Replay.Protocol.Types.Envelope matchedEnv) = matchedCommand.envelope
          let recordedStreamId = matchedEnv.streamId
          let recordedTraceId = matchedEnv.traceId
          let playbackStreamId = env.streamId
          let playbackTraceId = env.traceId

          Effect.Class.liftEffect $ markMessageUsed state matchIndex

          Effect.Class.liftEffect $ Effect.Ref.modify_
            ( Replay.IdTranslation.registerStreamIdMapping recordedStreamId playbackStreamId
                >>> Replay.IdTranslation.registerTraceIdMapping recordedTraceId playbackTraceId
            )
            state.translationMapRef

          case findCorrespondingResponse matchIndex recordedStreamId state.recording.messages of
            Data.Maybe.Nothing ->
              pure $ Data.Either.Left (InvalidRequest "No corresponding response found in recording")

            Data.Maybe.Just responseMessage -> do
              let translatedResponse = translateResponseEnvelope responseMessage.envelope commandEnvelope
              case translatedResponse of
                Data.Maybe.Just eventEnvelope ->
                  pure $ Data.Either.Right eventEnvelope
                Data.Maybe.Nothing ->
                  pure $ Data.Either.Left (UnexpectedPayload "Response message did not contain an Event")

    Replay.Protocol.Types.CommandClose ->
      pure $ Data.Either.Left (InvalidRequest "Unexpected CommandClose without open")

translateResponseEnvelope
  :: Replay.Protocol.Types.Envelope Replay.Recording.MessagePayload
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
  -> Data.Maybe.Maybe (Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event)
translateResponseEnvelope (Replay.Protocol.Types.Envelope recordedEnv) (Replay.Protocol.Types.Envelope playbackCommandEnv) =
  case recordedEnv.payload of
    Replay.Recording.PayloadEvent evt ->
      Data.Maybe.Just $ Replay.Protocol.Types.Envelope
        { streamId: playbackCommandEnv.streamId
        , traceId: playbackCommandEnv.traceId
        , causationStreamId: playbackCommandEnv.causationStreamId
        , parentStreamId: playbackCommandEnv.parentStreamId
        , siblingIndex: playbackCommandEnv.siblingIndex
        , eventSeq: recordedEnv.eventSeq
        , timestamp: recordedEnv.timestamp
        , channel: playbackCommandEnv.channel
        , payloadHash: Data.Maybe.Nothing
        , payload: evt
        }
    Replay.Recording.PayloadCommand _ ->
      Data.Maybe.Nothing
