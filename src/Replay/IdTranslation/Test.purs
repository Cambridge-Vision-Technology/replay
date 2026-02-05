module Replay.IdTranslation.Test
  ( runTests
  ) where

import Prelude

import Data.Maybe as Data.Maybe
import Json.Nullable as Json.Nullable
import Replay.Common as Replay.Common
import Replay.IdTranslation as Replay.IdTranslation
import Replay.Protocol.Types as Replay.Protocol.Types

testEmptyMapReturnsNothing :: Replay.Common.TestResult
testEmptyMapReturnsNothing =
  let
    translationMap = Replay.IdTranslation.emptyTranslationMap
    playbackId = Replay.Protocol.Types.StreamId "01PLAYBACK"
    result = Replay.IdTranslation.translateStreamIdToRecord playbackId translationMap
  in
    case result of
      Data.Maybe.Nothing ->
        Replay.Common.TestSuccess "Empty map returns Nothing for unknown StreamId"
      Data.Maybe.Just _ ->
        Replay.Common.TestFailure "Empty map returns Nothing for unknown StreamId" "Expected Nothing but got Just"

testRegisterMappingCreatesBidirectionalStreamId :: Replay.Common.TestResult
testRegisterMappingCreatesBidirectionalStreamId =
  let
    recordId = Replay.Protocol.Types.StreamId "01RECORD"
    playbackId = Replay.Protocol.Types.StreamId "01PLAYBACK"
    translationMap = Replay.IdTranslation.registerStreamIdMapping recordId playbackId Replay.IdTranslation.emptyTranslationMap
    toRecord = Replay.IdTranslation.translateStreamIdToRecord playbackId translationMap
    toPlayback = Replay.IdTranslation.translateStreamIdToPlayback recordId translationMap
  in
    case toRecord, toPlayback of
      Data.Maybe.Just r, Data.Maybe.Just p ->
        if r == recordId && p == playbackId then
          Replay.Common.TestSuccess "registerStreamIdMapping creates bidirectional mapping"
        else
          Replay.Common.TestFailure "registerStreamIdMapping creates bidirectional mapping" ("Got wrong values: " <> show r <> ", " <> show p)
      _, _ ->
        Replay.Common.TestFailure "registerStreamIdMapping creates bidirectional mapping" "Expected Just values but got Nothing"

testRegisterMappingCreatesBidirectionalTraceId :: Replay.Common.TestResult
testRegisterMappingCreatesBidirectionalTraceId =
  let
    recordId = Replay.Protocol.Types.TraceId "01RECORD"
    playbackId = Replay.Protocol.Types.TraceId "01PLAYBACK"
    translationMap = Replay.IdTranslation.registerTraceIdMapping recordId playbackId Replay.IdTranslation.emptyTranslationMap
    toRecord = Replay.IdTranslation.translateTraceIdToRecord playbackId translationMap
    toPlayback = Replay.IdTranslation.translateTraceIdToPlayback recordId translationMap
  in
    case toRecord, toPlayback of
      Data.Maybe.Just r, Data.Maybe.Just p ->
        if r == recordId && p == playbackId then
          Replay.Common.TestSuccess "registerTraceIdMapping creates bidirectional mapping"
        else
          Replay.Common.TestFailure "registerTraceIdMapping creates bidirectional mapping" ("Got wrong values: " <> show r <> ", " <> show p)
      _, _ ->
        Replay.Common.TestFailure "registerTraceIdMapping creates bidirectional mapping" "Expected Just values but got Nothing"

testTranslateStreamIdToRecordReturnsCorrectId :: Replay.Common.TestResult
testTranslateStreamIdToRecordReturnsCorrectId =
  let
    recordId = Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
    playbackId = Replay.Protocol.Types.StreamId "01XYZ9876543210ABCDEF12345"
    translationMap = Replay.IdTranslation.registerStreamIdMapping recordId playbackId Replay.IdTranslation.emptyTranslationMap
    result = Replay.IdTranslation.translateStreamIdToRecord playbackId translationMap
  in
    case result of
      Data.Maybe.Just id ->
        if id == recordId then
          Replay.Common.TestSuccess "translateStreamIdToRecord returns correct recording ID"
        else
          Replay.Common.TestFailure "translateStreamIdToRecord returns correct recording ID" ("Expected " <> show recordId <> " but got " <> show id)
      Data.Maybe.Nothing ->
        Replay.Common.TestFailure "translateStreamIdToRecord returns correct recording ID" "Expected Just but got Nothing"

testTranslateStreamIdToPlaybackReturnsCorrectId :: Replay.Common.TestResult
testTranslateStreamIdToPlaybackReturnsCorrectId =
  let
    recordId = Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
    playbackId = Replay.Protocol.Types.StreamId "01XYZ9876543210ABCDEF12345"
    translationMap = Replay.IdTranslation.registerStreamIdMapping recordId playbackId Replay.IdTranslation.emptyTranslationMap
    result = Replay.IdTranslation.translateStreamIdToPlayback recordId translationMap
  in
    case result of
      Data.Maybe.Just id ->
        if id == playbackId then
          Replay.Common.TestSuccess "translateStreamIdToPlayback returns correct playback ID"
        else
          Replay.Common.TestFailure "translateStreamIdToPlayback returns correct playback ID" ("Expected " <> show playbackId <> " but got " <> show id)
      Data.Maybe.Nothing ->
        Replay.Common.TestFailure "translateStreamIdToPlayback returns correct playback ID" "Expected Just but got Nothing"

testTranslateTraceIdToRecordReturnsCorrectId :: Replay.Common.TestResult
testTranslateTraceIdToRecordReturnsCorrectId =
  let
    recordId = Replay.Protocol.Types.TraceId "01TRACE_RECORD"
    playbackId = Replay.Protocol.Types.TraceId "01TRACE_PLAYBACK"
    translationMap = Replay.IdTranslation.registerTraceIdMapping recordId playbackId Replay.IdTranslation.emptyTranslationMap
    result = Replay.IdTranslation.translateTraceIdToRecord playbackId translationMap
  in
    case result of
      Data.Maybe.Just id ->
        if id == recordId then
          Replay.Common.TestSuccess "translateTraceIdToRecord returns correct recording ID"
        else
          Replay.Common.TestFailure "translateTraceIdToRecord returns correct recording ID" ("Expected " <> show recordId <> " but got " <> show id)
      Data.Maybe.Nothing ->
        Replay.Common.TestFailure "translateTraceIdToRecord returns correct recording ID" "Expected Just but got Nothing"

testTranslateTraceIdToPlaybackReturnsCorrectId :: Replay.Common.TestResult
testTranslateTraceIdToPlaybackReturnsCorrectId =
  let
    recordId = Replay.Protocol.Types.TraceId "01TRACE_RECORD"
    playbackId = Replay.Protocol.Types.TraceId "01TRACE_PLAYBACK"
    translationMap = Replay.IdTranslation.registerTraceIdMapping recordId playbackId Replay.IdTranslation.emptyTranslationMap
    result = Replay.IdTranslation.translateTraceIdToPlayback recordId translationMap
  in
    case result of
      Data.Maybe.Just id ->
        if id == playbackId then
          Replay.Common.TestSuccess "translateTraceIdToPlayback returns correct playback ID"
        else
          Replay.Common.TestFailure "translateTraceIdToPlayback returns correct playback ID" ("Expected " <> show playbackId <> " but got " <> show id)
      Data.Maybe.Nothing ->
        Replay.Common.TestFailure "translateTraceIdToPlayback returns correct playback ID" "Expected Just but got Nothing"

testUnknownStreamIdReturnsNothing :: Replay.Common.TestResult
testUnknownStreamIdReturnsNothing =
  let
    recordId = Replay.Protocol.Types.StreamId "01RECORD"
    playbackId = Replay.Protocol.Types.StreamId "01PLAYBACK"
    unknownId = Replay.Protocol.Types.StreamId "01UNKNOWN"
    translationMap = Replay.IdTranslation.registerStreamIdMapping recordId playbackId Replay.IdTranslation.emptyTranslationMap
    result = Replay.IdTranslation.translateStreamIdToRecord unknownId translationMap
  in
    case result of
      Data.Maybe.Nothing ->
        Replay.Common.TestSuccess "Unknown StreamId returns Nothing"
      Data.Maybe.Just _ ->
        Replay.Common.TestFailure "Unknown StreamId returns Nothing" "Expected Nothing but got Just"

testUnknownTraceIdReturnsNothing :: Replay.Common.TestResult
testUnknownTraceIdReturnsNothing =
  let
    recordId = Replay.Protocol.Types.TraceId "01RECORD"
    playbackId = Replay.Protocol.Types.TraceId "01PLAYBACK"
    unknownId = Replay.Protocol.Types.TraceId "01UNKNOWN"
    translationMap = Replay.IdTranslation.registerTraceIdMapping recordId playbackId Replay.IdTranslation.emptyTranslationMap
    result = Replay.IdTranslation.translateTraceIdToRecord unknownId translationMap
  in
    case result of
      Data.Maybe.Nothing ->
        Replay.Common.TestSuccess "Unknown TraceId returns Nothing"
      Data.Maybe.Just _ ->
        Replay.Common.TestFailure "Unknown TraceId returns Nothing" "Expected Nothing but got Just"

makeTestEnvelope :: Replay.Protocol.Types.StreamId -> Replay.Protocol.Types.TraceId -> Data.Maybe.Maybe Replay.Protocol.Types.StreamId -> Data.Maybe.Maybe Replay.Protocol.Types.StreamId -> Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
makeTestEnvelope streamId traceId causationStreamId parentStreamId =
  Replay.Protocol.Types.Envelope
    { streamId
    , traceId
    , causationStreamId: Json.Nullable.maybeToJsonNullable causationStreamId
    , parentStreamId: Json.Nullable.maybeToJsonNullable parentStreamId
    , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
    , eventSeq: Replay.Protocol.Types.EventSeq 0
    , timestamp: "2025-01-08T12:00:00.000Z"
    , channel: Replay.Protocol.Types.ProgramChannel
    , payloadHash: Data.Maybe.Nothing
    , payload: Replay.Protocol.Types.CommandClose
    }

testTranslateEnvelopeToRecordTranslatesAllIds :: Replay.Common.TestResult
testTranslateEnvelopeToRecordTranslatesAllIds =
  let
    recordStreamId = Replay.Protocol.Types.StreamId "01REC_STREAM"
    playbackStreamId = Replay.Protocol.Types.StreamId "01PLAY_STREAM"
    recordTraceId = Replay.Protocol.Types.TraceId "01REC_TRACE"
    playbackTraceId = Replay.Protocol.Types.TraceId "01PLAY_TRACE"
    recordCausationId = Replay.Protocol.Types.StreamId "01REC_CAUSE"
    playbackCausationId = Replay.Protocol.Types.StreamId "01PLAY_CAUSE"
    recordParentId = Replay.Protocol.Types.StreamId "01REC_PARENT"
    playbackParentId = Replay.Protocol.Types.StreamId "01PLAY_PARENT"

    translationMap =
      Replay.IdTranslation.emptyTranslationMap
        # Replay.IdTranslation.registerStreamIdMapping recordStreamId playbackStreamId
        # Replay.IdTranslation.registerTraceIdMapping recordTraceId playbackTraceId
        # Replay.IdTranslation.registerStreamIdMapping recordCausationId playbackCausationId
        # Replay.IdTranslation.registerStreamIdMapping recordParentId playbackParentId

    playbackEnvelope = makeTestEnvelope playbackStreamId playbackTraceId (Data.Maybe.Just playbackCausationId) (Data.Maybe.Just playbackParentId)

    (Replay.Protocol.Types.Envelope translatedEnv) = Replay.IdTranslation.translateEnvelopeToRecord translationMap playbackEnvelope

    translatedCausation = Json.Nullable.jsonNullableToMaybe translatedEnv.causationStreamId
    translatedParent = Json.Nullable.jsonNullableToMaybe translatedEnv.parentStreamId
  in
    if
      translatedEnv.streamId == recordStreamId
        && translatedEnv.traceId == recordTraceId
        && translatedCausation == Data.Maybe.Just recordCausationId
        && translatedParent == Data.Maybe.Just recordParentId then
      Replay.Common.TestSuccess "translateEnvelopeToRecord translates all ID fields"
    else
      Replay.Common.TestFailure "translateEnvelopeToRecord translates all ID fields"
        ( "streamId: " <> show translatedEnv.streamId <> " (expected " <> show recordStreamId <> "), "
            <> "traceId: "
            <> show translatedEnv.traceId
            <> " (expected "
            <> show recordTraceId
            <> "), "
            <> "causationStreamId: "
            <> show translatedCausation
            <> " (expected Just "
            <> show recordCausationId
            <> "), "
            <> "parentStreamId: "
            <> show translatedParent
            <> " (expected Just "
            <> show recordParentId
            <> ")"
        )

testTranslateEnvelopeToPlaybackTranslatesAllIds :: Replay.Common.TestResult
testTranslateEnvelopeToPlaybackTranslatesAllIds =
  let
    recordStreamId = Replay.Protocol.Types.StreamId "01REC_STREAM"
    playbackStreamId = Replay.Protocol.Types.StreamId "01PLAY_STREAM"
    recordTraceId = Replay.Protocol.Types.TraceId "01REC_TRACE"
    playbackTraceId = Replay.Protocol.Types.TraceId "01PLAY_TRACE"
    recordCausationId = Replay.Protocol.Types.StreamId "01REC_CAUSE"
    playbackCausationId = Replay.Protocol.Types.StreamId "01PLAY_CAUSE"
    recordParentId = Replay.Protocol.Types.StreamId "01REC_PARENT"
    playbackParentId = Replay.Protocol.Types.StreamId "01PLAY_PARENT"

    translationMap =
      Replay.IdTranslation.emptyTranslationMap
        # Replay.IdTranslation.registerStreamIdMapping recordStreamId playbackStreamId
        # Replay.IdTranslation.registerTraceIdMapping recordTraceId playbackTraceId
        # Replay.IdTranslation.registerStreamIdMapping recordCausationId playbackCausationId
        # Replay.IdTranslation.registerStreamIdMapping recordParentId playbackParentId

    recordEnvelope = makeTestEnvelope recordStreamId recordTraceId (Data.Maybe.Just recordCausationId) (Data.Maybe.Just recordParentId)

    (Replay.Protocol.Types.Envelope translatedEnv) = Replay.IdTranslation.translateEnvelopeToPlayback translationMap recordEnvelope

    translatedCausation = Json.Nullable.jsonNullableToMaybe translatedEnv.causationStreamId
    translatedParent = Json.Nullable.jsonNullableToMaybe translatedEnv.parentStreamId
  in
    if
      translatedEnv.streamId == playbackStreamId
        && translatedEnv.traceId == playbackTraceId
        && translatedCausation == Data.Maybe.Just playbackCausationId
        && translatedParent == Data.Maybe.Just playbackParentId then
      Replay.Common.TestSuccess "translateEnvelopeToPlayback translates all ID fields"
    else
      Replay.Common.TestFailure "translateEnvelopeToPlayback translates all ID fields"
        ( "streamId: " <> show translatedEnv.streamId <> " (expected " <> show playbackStreamId <> "), "
            <> "traceId: "
            <> show translatedEnv.traceId
            <> " (expected "
            <> show playbackTraceId
            <> "), "
            <> "causationStreamId: "
            <> show translatedCausation
            <> " (expected Just "
            <> show playbackCausationId
            <> "), "
            <> "parentStreamId: "
            <> show translatedParent
            <> " (expected Just "
            <> show playbackParentId
            <> ")"
        )

testTranslateEnvelopeWithNullIds :: Replay.Common.TestResult
testTranslateEnvelopeWithNullIds =
  let
    recordStreamId = Replay.Protocol.Types.StreamId "01REC_STREAM"
    playbackStreamId = Replay.Protocol.Types.StreamId "01PLAY_STREAM"
    recordTraceId = Replay.Protocol.Types.TraceId "01REC_TRACE"
    playbackTraceId = Replay.Protocol.Types.TraceId "01PLAY_TRACE"

    translationMap =
      Replay.IdTranslation.emptyTranslationMap
        # Replay.IdTranslation.registerStreamIdMapping recordStreamId playbackStreamId
        # Replay.IdTranslation.registerTraceIdMapping recordTraceId playbackTraceId

    playbackEnvelope = makeTestEnvelope playbackStreamId playbackTraceId Data.Maybe.Nothing Data.Maybe.Nothing

    (Replay.Protocol.Types.Envelope translatedEnv) = Replay.IdTranslation.translateEnvelopeToRecord translationMap playbackEnvelope

    translatedCausation = Json.Nullable.jsonNullableToMaybe translatedEnv.causationStreamId
    translatedParent = Json.Nullable.jsonNullableToMaybe translatedEnv.parentStreamId
  in
    if
      translatedEnv.streamId == recordStreamId
        && translatedEnv.traceId == recordTraceId
        && translatedCausation == Data.Maybe.Nothing
        && translatedParent == Data.Maybe.Nothing then
      Replay.Common.TestSuccess "translateEnvelope preserves null causation and parent IDs"
    else
      Replay.Common.TestFailure "translateEnvelope preserves null causation and parent IDs"
        ( "causationStreamId: " <> show translatedCausation <> " (expected Nothing), "
            <> "parentStreamId: "
            <> show translatedParent
            <> " (expected Nothing)"
        )

testTranslateEnvelopeWithUnknownIdsFallsBackToOriginal :: Replay.Common.TestResult
testTranslateEnvelopeWithUnknownIdsFallsBackToOriginal =
  let
    unknownStreamId = Replay.Protocol.Types.StreamId "01UNKNOWN_STREAM"
    unknownTraceId = Replay.Protocol.Types.TraceId "01UNKNOWN_TRACE"

    translationMap = Replay.IdTranslation.emptyTranslationMap

    envelope = makeTestEnvelope unknownStreamId unknownTraceId Data.Maybe.Nothing Data.Maybe.Nothing

    (Replay.Protocol.Types.Envelope translatedEnv) = Replay.IdTranslation.translateEnvelopeToRecord translationMap envelope
  in
    if translatedEnv.streamId == unknownStreamId && translatedEnv.traceId == unknownTraceId then
      Replay.Common.TestSuccess "translateEnvelope falls back to original when ID is unknown"
    else
      Replay.Common.TestFailure "translateEnvelope falls back to original when ID is unknown"
        ( "streamId: " <> show translatedEnv.streamId <> " (expected " <> show unknownStreamId <> "), "
            <> "traceId: "
            <> show translatedEnv.traceId
            <> " (expected "
            <> show unknownTraceId
            <> ")"
        )

testMultipleMappings :: Replay.Common.TestResult
testMultipleMappings =
  let
    recordId1 = Replay.Protocol.Types.StreamId "01REC1"
    playbackId1 = Replay.Protocol.Types.StreamId "01PLAY1"
    recordId2 = Replay.Protocol.Types.StreamId "01REC2"
    playbackId2 = Replay.Protocol.Types.StreamId "01PLAY2"
    recordId3 = Replay.Protocol.Types.StreamId "01REC3"
    playbackId3 = Replay.Protocol.Types.StreamId "01PLAY3"

    translationMap =
      Replay.IdTranslation.emptyTranslationMap
        # Replay.IdTranslation.registerStreamIdMapping recordId1 playbackId1
        # Replay.IdTranslation.registerStreamIdMapping recordId2 playbackId2
        # Replay.IdTranslation.registerStreamIdMapping recordId3 playbackId3

    result1 = Replay.IdTranslation.translateStreamIdToRecord playbackId1 translationMap
    result2 = Replay.IdTranslation.translateStreamIdToRecord playbackId2 translationMap
    result3 = Replay.IdTranslation.translateStreamIdToRecord playbackId3 translationMap
  in
    case result1, result2, result3 of
      Data.Maybe.Just r1, Data.Maybe.Just r2, Data.Maybe.Just r3 ->
        if r1 == recordId1 && r2 == recordId2 && r3 == recordId3 then
          Replay.Common.TestSuccess "Multiple mappings work correctly"
        else
          Replay.Common.TestFailure "Multiple mappings work correctly" "Got wrong values for one or more mappings"
      _, _, _ ->
        Replay.Common.TestFailure "Multiple mappings work correctly" "Expected Just values but got Nothing for one or more"

testEnvelopePreservesNonIdFields :: Replay.Common.TestResult
testEnvelopePreservesNonIdFields =
  let
    recordStreamId = Replay.Protocol.Types.StreamId "01REC_STREAM"
    playbackStreamId = Replay.Protocol.Types.StreamId "01PLAY_STREAM"
    recordTraceId = Replay.Protocol.Types.TraceId "01REC_TRACE"
    playbackTraceId = Replay.Protocol.Types.TraceId "01PLAY_TRACE"

    translationMap =
      Replay.IdTranslation.emptyTranslationMap
        # Replay.IdTranslation.registerStreamIdMapping recordStreamId playbackStreamId
        # Replay.IdTranslation.registerTraceIdMapping recordTraceId playbackTraceId

    originalSiblingIndex = Replay.Protocol.Types.SiblingIndex 42
    originalEventSeq = Replay.Protocol.Types.EventSeq 99
    originalTimestamp = "2025-12-25T00:00:00.000Z"
    originalPayload = Replay.Protocol.Types.CommandClose

    playbackEnvelope = Replay.Protocol.Types.Envelope
      { streamId: playbackStreamId
      , traceId: playbackTraceId
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: originalSiblingIndex
      , eventSeq: originalEventSeq
      , timestamp: originalTimestamp
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: originalPayload
      }

    (Replay.Protocol.Types.Envelope translatedEnv) = Replay.IdTranslation.translateEnvelopeToRecord translationMap playbackEnvelope
    payloadMatches = show translatedEnv.payload == show originalPayload
  in
    if
      translatedEnv.siblingIndex == originalSiblingIndex
        && translatedEnv.eventSeq == originalEventSeq
        && translatedEnv.timestamp == originalTimestamp
        && payloadMatches then
      Replay.Common.TestSuccess "translateEnvelope preserves non-ID fields"
    else
      Replay.Common.TestFailure "translateEnvelope preserves non-ID fields" "One or more non-ID fields were modified"

allTests :: Array Replay.Common.TestResult
allTests =
  [ testEmptyMapReturnsNothing
  , testRegisterMappingCreatesBidirectionalStreamId
  , testRegisterMappingCreatesBidirectionalTraceId
  , testTranslateStreamIdToRecordReturnsCorrectId
  , testTranslateStreamIdToPlaybackReturnsCorrectId
  , testTranslateTraceIdToRecordReturnsCorrectId
  , testTranslateTraceIdToPlaybackReturnsCorrectId
  , testUnknownStreamIdReturnsNothing
  , testUnknownTraceIdReturnsNothing
  , testTranslateEnvelopeToRecordTranslatesAllIds
  , testTranslateEnvelopeToPlaybackTranslatesAllIds
  , testTranslateEnvelopeWithNullIds
  , testTranslateEnvelopeWithUnknownIdsFallsBackToOriginal
  , testMultipleMappings
  , testEnvelopePreservesNonIdFields
  ]

runTests :: Replay.Common.TestResults
runTests = Replay.Common.computeResults allTests
