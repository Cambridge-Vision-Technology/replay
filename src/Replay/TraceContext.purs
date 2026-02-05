module Replay.TraceContext
  ( TraceContext
  , newTrace
  , childContext
  , siblingContext
  , withCausation
  , generateStreamId
  , traceId
  , parentStreamId
  , causationStreamId
  , siblingIndex
  , currentStreamId
  ) where

import Prelude

import Data.Maybe as Data.Maybe
import Data.Newtype as Data.Newtype
import Effect as Effect
import Replay.Protocol.Types as Replay.Protocol.Types
import Replay.ULID as Replay.ULID

-- ============================================================================
-- TraceContext Type
-- ============================================================================

-- | TraceContext tracks the identity and lineage of streams within a trace.
-- |
-- | - `traceId`: Root trace identity (constant within a saga)
-- | - `currentStreamId`: The stream ID for this context
-- | - `parentStreamId`: Parent stream (Nothing at root)
-- | - `causationStreamId`: Stream that caused this one (for response correlation)
-- | - `siblingIndex`: Which parallel slot under parent (0 for sequential ops)
type TraceContext =
  { traceId :: Replay.Protocol.Types.TraceId
  , currentStreamId :: Replay.Protocol.Types.StreamId
  , parentStreamId :: Data.Maybe.Maybe Replay.Protocol.Types.StreamId
  , causationStreamId :: Data.Maybe.Maybe Replay.Protocol.Types.StreamId
  , siblingIndex :: Replay.Protocol.Types.SiblingIndex
  }

-- ============================================================================
-- Context Accessors
-- ============================================================================

traceId :: TraceContext -> Replay.Protocol.Types.TraceId
traceId ctx = ctx.traceId

parentStreamId :: TraceContext -> Data.Maybe.Maybe Replay.Protocol.Types.StreamId
parentStreamId ctx = ctx.parentStreamId

causationStreamId :: TraceContext -> Data.Maybe.Maybe Replay.Protocol.Types.StreamId
causationStreamId ctx = ctx.causationStreamId

siblingIndex :: TraceContext -> Replay.Protocol.Types.SiblingIndex
siblingIndex ctx = ctx.siblingIndex

currentStreamId :: TraceContext -> Replay.Protocol.Types.StreamId
currentStreamId ctx = ctx.currentStreamId

-- ============================================================================
-- Context Operations
-- ============================================================================

-- | Generate a new StreamId using ULID
generateStreamId :: Effect.Effect Replay.Protocol.Types.StreamId
generateStreamId = do
  ulid <- Replay.ULID.generate
  pure $ Replay.Protocol.Types.StreamId (Replay.ULID.toString ulid)

-- | Create a new root trace context.
-- | This generates a new TraceId and StreamId for the root of a trace (saga).
newTrace :: Effect.Effect TraceContext
newTrace = do
  ulid <- Replay.ULID.generate
  let idStr = Replay.ULID.toString ulid
  pure
    { traceId: Replay.Protocol.Types.TraceId idStr
    , currentStreamId: Replay.Protocol.Types.StreamId idStr
    , parentStreamId: Data.Maybe.Nothing
    , causationStreamId: Data.Maybe.Nothing
    , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
    }

-- | Create a child context for a sequential operation.
-- | The child inherits the traceId but gets a new streamId.
-- | The parent's currentStreamId becomes the child's parentStreamId.
-- | SiblingIndex is reset to 0 for the new scope.
childContext :: TraceContext -> Effect.Effect TraceContext
childContext parent = do
  newStreamId <- generateStreamId
  pure
    { traceId: parent.traceId
    , currentStreamId: newStreamId
    , parentStreamId: Data.Maybe.Just parent.currentStreamId
    , causationStreamId: parent.causationStreamId
    , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
    }

-- | Create a sibling context for a parallel operation.
-- | The sibling shares the same traceId and parentStreamId as the original,
-- | but has a different siblingIndex to distinguish parallel slots.
-- | A new streamId is generated for this sibling.
siblingContext :: TraceContext -> Replay.Protocol.Types.SiblingIndex -> Effect.Effect TraceContext
siblingContext ctx newSiblingIndex = do
  newStreamId <- generateStreamId
  pure
    { traceId: ctx.traceId
    , currentStreamId: newStreamId
    , parentStreamId: ctx.parentStreamId
    , causationStreamId: ctx.causationStreamId
    , siblingIndex: newSiblingIndex
    }

-- | Set the causation stream ID on a context.
-- | This is used to track which stream's response caused this stream to be created.
withCausation :: Replay.Protocol.Types.StreamId -> TraceContext -> TraceContext
withCausation causation ctx = ctx { causationStreamId = Data.Maybe.Just causation }
