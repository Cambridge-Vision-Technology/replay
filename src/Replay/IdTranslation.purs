module Replay.IdTranslation
  ( TranslationMap
  , emptyTranslationMap
  , registerStreamIdMapping
  , registerTraceIdMapping
  , translateStreamIdToRecord
  , translateStreamIdToPlayback
  , translateTraceIdToRecord
  , translateTraceIdToPlayback
  , translateEnvelopeToRecord
  , translateEnvelopeToPlayback
  ) where

import Prelude

import Data.Map as Data.Map
import Data.Maybe as Data.Maybe
import Json.Nullable as Json.Nullable
import Replay.Protocol.Types as Replay.Protocol.Types

type TranslationMap =
  { streamIdRecordToPlayback :: Data.Map.Map Replay.Protocol.Types.StreamId Replay.Protocol.Types.StreamId
  , streamIdPlaybackToRecord :: Data.Map.Map Replay.Protocol.Types.StreamId Replay.Protocol.Types.StreamId
  , traceIdRecordToPlayback :: Data.Map.Map Replay.Protocol.Types.TraceId Replay.Protocol.Types.TraceId
  , traceIdPlaybackToRecord :: Data.Map.Map Replay.Protocol.Types.TraceId Replay.Protocol.Types.TraceId
  }

emptyTranslationMap :: TranslationMap
emptyTranslationMap =
  { streamIdRecordToPlayback: Data.Map.empty
  , streamIdPlaybackToRecord: Data.Map.empty
  , traceIdRecordToPlayback: Data.Map.empty
  , traceIdPlaybackToRecord: Data.Map.empty
  }

registerStreamIdMapping
  :: Replay.Protocol.Types.StreamId
  -> Replay.Protocol.Types.StreamId
  -> TranslationMap
  -> TranslationMap
registerStreamIdMapping recordId playbackId translationMap =
  translationMap
    { streamIdRecordToPlayback = Data.Map.insert recordId playbackId translationMap.streamIdRecordToPlayback
    , streamIdPlaybackToRecord = Data.Map.insert playbackId recordId translationMap.streamIdPlaybackToRecord
    }

registerTraceIdMapping
  :: Replay.Protocol.Types.TraceId
  -> Replay.Protocol.Types.TraceId
  -> TranslationMap
  -> TranslationMap
registerTraceIdMapping recordId playbackId translationMap =
  translationMap
    { traceIdRecordToPlayback = Data.Map.insert recordId playbackId translationMap.traceIdRecordToPlayback
    , traceIdPlaybackToRecord = Data.Map.insert playbackId recordId translationMap.traceIdPlaybackToRecord
    }

translateStreamIdToRecord
  :: Replay.Protocol.Types.StreamId
  -> TranslationMap
  -> Data.Maybe.Maybe Replay.Protocol.Types.StreamId
translateStreamIdToRecord playbackId translationMap =
  Data.Map.lookup playbackId translationMap.streamIdPlaybackToRecord

translateStreamIdToPlayback
  :: Replay.Protocol.Types.StreamId
  -> TranslationMap
  -> Data.Maybe.Maybe Replay.Protocol.Types.StreamId
translateStreamIdToPlayback recordId translationMap =
  Data.Map.lookup recordId translationMap.streamIdRecordToPlayback

translateTraceIdToRecord
  :: Replay.Protocol.Types.TraceId
  -> TranslationMap
  -> Data.Maybe.Maybe Replay.Protocol.Types.TraceId
translateTraceIdToRecord playbackId translationMap =
  Data.Map.lookup playbackId translationMap.traceIdPlaybackToRecord

translateTraceIdToPlayback
  :: Replay.Protocol.Types.TraceId
  -> TranslationMap
  -> Data.Maybe.Maybe Replay.Protocol.Types.TraceId
translateTraceIdToPlayback recordId translationMap =
  Data.Map.lookup recordId translationMap.traceIdRecordToPlayback

translateEnvelopeToRecord
  :: forall a
   . TranslationMap
  -> Replay.Protocol.Types.Envelope a
  -> Replay.Protocol.Types.Envelope a
translateEnvelopeToRecord translationMap (Replay.Protocol.Types.Envelope env) =
  Replay.Protocol.Types.Envelope env
    { streamId = translateStreamIdWithFallback translateStreamIdToRecord env.streamId translationMap
    , traceId = translateTraceIdWithFallback translateTraceIdToRecord env.traceId translationMap
    , causationStreamId = translateNullableStreamIdWithFallback translateStreamIdToRecord env.causationStreamId translationMap
    , parentStreamId = translateNullableStreamIdWithFallback translateStreamIdToRecord env.parentStreamId translationMap
    }

translateEnvelopeToPlayback
  :: forall a
   . TranslationMap
  -> Replay.Protocol.Types.Envelope a
  -> Replay.Protocol.Types.Envelope a
translateEnvelopeToPlayback translationMap (Replay.Protocol.Types.Envelope env) =
  Replay.Protocol.Types.Envelope env
    { streamId = translateStreamIdWithFallback translateStreamIdToPlayback env.streamId translationMap
    , traceId = translateTraceIdWithFallback translateTraceIdToPlayback env.traceId translationMap
    , causationStreamId = translateNullableStreamIdWithFallback translateStreamIdToPlayback env.causationStreamId translationMap
    , parentStreamId = translateNullableStreamIdWithFallback translateStreamIdToPlayback env.parentStreamId translationMap
    }

translateStreamIdWithFallback
  :: (Replay.Protocol.Types.StreamId -> TranslationMap -> Data.Maybe.Maybe Replay.Protocol.Types.StreamId)
  -> Replay.Protocol.Types.StreamId
  -> TranslationMap
  -> Replay.Protocol.Types.StreamId
translateStreamIdWithFallback translateFn streamId translationMap =
  Data.Maybe.fromMaybe streamId (translateFn streamId translationMap)

translateTraceIdWithFallback
  :: (Replay.Protocol.Types.TraceId -> TranslationMap -> Data.Maybe.Maybe Replay.Protocol.Types.TraceId)
  -> Replay.Protocol.Types.TraceId
  -> TranslationMap
  -> Replay.Protocol.Types.TraceId
translateTraceIdWithFallback translateFn traceId translationMap =
  Data.Maybe.fromMaybe traceId (translateFn traceId translationMap)

translateNullableStreamIdWithFallback
  :: (Replay.Protocol.Types.StreamId -> TranslationMap -> Data.Maybe.Maybe Replay.Protocol.Types.StreamId)
  -> Json.Nullable.JsonNullable Replay.Protocol.Types.StreamId
  -> TranslationMap
  -> Json.Nullable.JsonNullable Replay.Protocol.Types.StreamId
translateNullableStreamIdWithFallback translateFn nullableStreamId translationMap =
  case Json.Nullable.jsonNullableToMaybe nullableStreamId of
    Data.Maybe.Nothing ->
      Json.Nullable.jsonNull
    Data.Maybe.Just streamId ->
      Json.Nullable.jsonNotNull (translateStreamIdWithFallback translateFn streamId translationMap)
