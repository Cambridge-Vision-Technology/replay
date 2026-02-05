module Replay.PendingRequests
  ( PendingRequestsState
  , PendingRequestsMap
  , PendingRequestError(..)
  , ResponseCallback
  , createPendingRequestsState
  , registerRequest
  , resolveRequest
  , resolveRequestWithError
  , cancelAllPending
  , getPendingCount
  ) where

import Prelude

import Data.Either as Data.Either
import Data.List as Data.List
import Data.Map as Data.Map
import Data.Maybe as Data.Maybe
import Effect as Effect
import Effect.Ref as Effect.Ref
import Replay.Protocol.Types as Replay.Protocol.Types

data PendingRequestError
  = RequestTimeout Replay.Protocol.Types.StreamId
  | ConnectionClosed
  | UnexpectedError String

derive instance Eq PendingRequestError

instance Show PendingRequestError where
  show (RequestTimeout streamId) = "RequestTimeout: " <> show streamId
  show ConnectionClosed = "ConnectionClosed"
  show (UnexpectedError msg) = "UnexpectedError: " <> msg

type ResponseCallback =
  Data.Either.Either PendingRequestError Replay.Protocol.Types.ResponsePayload -> Effect.Effect Unit

type PendingRequestsMap = Data.Map.Map Replay.Protocol.Types.StreamId ResponseCallback

type PendingRequestsState =
  { pendingRef :: Effect.Ref.Ref PendingRequestsMap
  }

createPendingRequestsState :: Effect.Effect PendingRequestsState
createPendingRequestsState = do
  pendingRef <- Effect.Ref.new Data.Map.empty
  pure { pendingRef }

registerRequest
  :: PendingRequestsState
  -> Replay.Protocol.Types.StreamId
  -> ResponseCallback
  -> Effect.Effect Unit
registerRequest state streamId callback =
  Effect.Ref.modify_ (Data.Map.insert streamId callback) state.pendingRef

resolveRequest
  :: PendingRequestsState
  -> Replay.Protocol.Types.StreamId
  -> Replay.Protocol.Types.ResponsePayload
  -> Effect.Effect Boolean
resolveRequest state streamId response = do
  pending <- Effect.Ref.read state.pendingRef
  case Data.Map.lookup streamId pending of
    Data.Maybe.Nothing ->
      pure false
    Data.Maybe.Just callback -> do
      Effect.Ref.modify_ (Data.Map.delete streamId) state.pendingRef
      callback (Data.Either.Right response)
      pure true

resolveRequestWithError
  :: PendingRequestsState
  -> Replay.Protocol.Types.StreamId
  -> PendingRequestError
  -> Effect.Effect Boolean
resolveRequestWithError state streamId requestError = do
  pending <- Effect.Ref.read state.pendingRef
  case Data.Map.lookup streamId pending of
    Data.Maybe.Nothing ->
      pure false
    Data.Maybe.Just callback -> do
      Effect.Ref.modify_ (Data.Map.delete streamId) state.pendingRef
      callback (Data.Either.Left requestError)
      pure true

cancelAllPending
  :: PendingRequestsState
  -> PendingRequestError
  -> Effect.Effect Int
cancelAllPending state requestError = do
  pending <- Effect.Ref.read state.pendingRef
  Effect.Ref.write Data.Map.empty state.pendingRef
  let callbacks = Data.Map.values pending
  cancelAll callbacks 0
  where
  cancelAll :: Data.List.List ResponseCallback -> Int -> Effect.Effect Int
  cancelAll callbacks count = case Data.List.uncons callbacks of
    Data.Maybe.Nothing ->
      pure count
    Data.Maybe.Just { head: callback, tail: rest } -> do
      callback (Data.Either.Left requestError)
      cancelAll rest (count + 1)

getPendingCount :: PendingRequestsState -> Effect.Effect Int
getPendingCount state = do
  pending <- Effect.Ref.read state.pendingRef
  pure (Data.Map.size pending)
