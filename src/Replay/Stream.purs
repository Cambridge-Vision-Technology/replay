module Replay.Stream
  ( StreamState(..)
  , OpenEvent
  , CloseEvent
  , createOpenEvent
  , createCloseEvent
  , nowISOString
  , openEventSeq
  , closeEventSeq
  ) where

import Prelude

import Data.Maybe as Data.Maybe
import Effect as Effect
import Json.Nullable as Json.Nullable
import Replay.TraceContext as Replay.TraceContext
import Replay.Protocol.Types as Replay.Protocol.Types

-- ============================================================================
-- FFI
-- ============================================================================

foreign import nowISOStringImpl :: Effect.Effect String

nowISOString :: Effect.Effect String
nowISOString = nowISOStringImpl

-- ============================================================================
-- Stream State Types
-- ============================================================================

data StreamState
  = StreamOpen
  | StreamClosed

derive instance Eq StreamState
derive instance Ord StreamState

instance Show StreamState where
  show StreamOpen = "StreamOpen"
  show StreamClosed = "StreamClosed"

-- ============================================================================
-- Event Emission Types
-- ============================================================================

type OpenEvent = Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command

type CloseEvent = Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event

-- ============================================================================
-- Event Sequence Constants
-- ============================================================================

openEventSeq :: Replay.Protocol.Types.EventSeq
openEventSeq = Replay.Protocol.Types.EventSeq 0

closeEventSeq :: Replay.Protocol.Types.EventSeq
closeEventSeq = Replay.Protocol.Types.EventSeq 1

-- ============================================================================
-- Lifecycle Functions
-- ============================================================================

createOpenEvent
  :: Replay.TraceContext.TraceContext
  -> Replay.Protocol.Types.Channel
  -> Replay.Protocol.Types.RequestPayload
  -> Effect.Effect OpenEvent
createOpenEvent ctx channel requestPayload = do
  timestamp <- nowISOString
  pure $ Replay.Protocol.Types.Envelope
    { streamId: Replay.TraceContext.currentStreamId ctx
    , traceId: Replay.TraceContext.traceId ctx
    , causationStreamId: Json.Nullable.maybeToJsonNullable (Replay.TraceContext.causationStreamId ctx)
    , parentStreamId: Json.Nullable.maybeToJsonNullable (Replay.TraceContext.parentStreamId ctx)
    , siblingIndex: Replay.TraceContext.siblingIndex ctx
    , eventSeq: openEventSeq
    , timestamp
    , channel
    , payloadHash: Data.Maybe.Nothing
    , payload: Replay.Protocol.Types.CommandOpen requestPayload
    }

createCloseEvent
  :: Replay.TraceContext.TraceContext
  -> Replay.Protocol.Types.StreamId
  -> Replay.Protocol.Types.Channel
  -> Replay.Protocol.Types.ResponsePayload
  -> Effect.Effect CloseEvent
createCloseEvent ctx streamId channel responsePayload = do
  timestamp <- nowISOString
  pure $ Replay.Protocol.Types.Envelope
    { streamId
    , traceId: Replay.TraceContext.traceId ctx
    , causationStreamId: Json.Nullable.maybeToJsonNullable (Replay.TraceContext.causationStreamId ctx)
    , parentStreamId: Json.Nullable.maybeToJsonNullable (Replay.TraceContext.parentStreamId ctx)
    , siblingIndex: Replay.TraceContext.siblingIndex ctx
    , eventSeq: closeEventSeq
    , timestamp
    , channel
    , payloadHash: Data.Maybe.Nothing
    , payload: Replay.Protocol.Types.EventClose responsePayload
    }
