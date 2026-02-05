module Replay.Protocol.Envelope
  ( buildResponseEnvelope
  , buildRequestEnvelope
  ) where

import Prelude

import Data.Maybe as Data.Maybe
import Json.Nullable as Json.Nullable
import Replay.TraceContext as Replay.TraceContext
import Replay.Protocol.Types as Replay.Protocol.Types

-- | Build a request envelope from trace context, timestamp, hash, and payload.
-- | This reduces boilerplate in harness handlers by encapsulating the common
-- | envelope construction pattern.
buildRequestEnvelope
  :: Replay.TraceContext.TraceContext
  -> String
  -> String
  -> Replay.Protocol.Types.RequestPayload
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
buildRequestEnvelope traceCtx timestamp payloadHash requestPayload =
  Replay.Protocol.Types.Envelope
    { streamId: Replay.TraceContext.currentStreamId traceCtx
    , traceId: Replay.TraceContext.traceId traceCtx
    , causationStreamId: Json.Nullable.jsonNull
    , parentStreamId: Json.Nullable.jsonNull
    , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
    , eventSeq: Replay.Protocol.Types.EventSeq 0
    , timestamp
    , channel: Replay.Protocol.Types.ProgramChannel
    , payloadHash: Data.Maybe.Just payloadHash
    , payload: Replay.Protocol.Types.CommandOpen requestPayload
    }

-- | Build a response envelope from command envelope fields
-- | Uses row polymorphism to accept any record with the required routing fields
buildResponseEnvelope
  :: forall r
   . { streamId :: Replay.Protocol.Types.StreamId
     , traceId :: Replay.Protocol.Types.TraceId
     , causationStreamId :: Json.Nullable.JsonNullable Replay.Protocol.Types.StreamId
     , parentStreamId :: Json.Nullable.JsonNullable Replay.Protocol.Types.StreamId
     , siblingIndex :: Replay.Protocol.Types.SiblingIndex
     , channel :: Replay.Protocol.Types.Channel
     | r
     }
  -> String
  -> Replay.Protocol.Types.ResponsePayload
  -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Event
buildResponseEnvelope env timestamp responsePayload =
  Replay.Protocol.Types.Envelope
    { streamId: env.streamId
    , traceId: env.traceId
    , causationStreamId: env.causationStreamId
    , parentStreamId: env.parentStreamId
    , siblingIndex: env.siblingIndex
    , eventSeq: Replay.Protocol.Types.EventSeq 1
    , timestamp
    , channel: env.channel
    , payloadHash: Data.Maybe.Nothing
    , payload: Replay.Protocol.Types.EventClose responsePayload
    }
