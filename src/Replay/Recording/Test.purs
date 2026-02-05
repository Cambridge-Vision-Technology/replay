module Replay.Recording.Test
  ( runTests
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Maybe as Data.Maybe
import Data.String as Data.String
import Effect.Aff as Effect.Aff
import Json.Nullable as Json.Nullable
import Node.Encoding as Node.Encoding
import Node.FS.Aff as Node.FS.Aff
import Node.FS.Perms as Node.FS.Perms
import Replay.Common as Replay.Common
import Replay.Recording as Replay.Recording
import Replay.Protocol.Types as Replay.Protocol.Types

testSchemaVersionValidCurrent :: Replay.Common.TestResult
testSchemaVersionValidCurrent =
  let
    result = Replay.Recording.validateSchemaVersion Replay.Recording.currentSchemaVersion
  in
    case result of
      Replay.Recording.SchemaValid ->
        Replay.Common.TestSuccess "validateSchemaVersion returns SchemaValid for current version"
      Replay.Recording.SchemaIncompatible _ ->
        Replay.Common.TestFailure "validateSchemaVersion returns SchemaValid for current version"
          "Returned SchemaIncompatible for current version"

testSchemaVersionInvalidOld :: Replay.Common.TestResult
testSchemaVersionInvalidOld =
  let
    result = Replay.Recording.validateSchemaVersion 0
  in
    case result of
      Replay.Recording.SchemaIncompatible { found, expected } ->
        if found == 0 && expected == Replay.Recording.currentSchemaVersion then
          Replay.Common.TestSuccess "validateSchemaVersion returns SchemaIncompatible for old version"
        else
          Replay.Common.TestFailure "validateSchemaVersion returns SchemaIncompatible for old version"
            ("Wrong found/expected: " <> show found <> "/" <> show expected)
      Replay.Recording.SchemaValid ->
        Replay.Common.TestFailure "validateSchemaVersion returns SchemaIncompatible for old version"
          "Returned SchemaValid for old version"

testSchemaVersionInvalidFuture :: Replay.Common.TestResult
testSchemaVersionInvalidFuture =
  let
    futureVersion = Replay.Recording.currentSchemaVersion + 1
    result = Replay.Recording.validateSchemaVersion futureVersion
  in
    case result of
      Replay.Recording.SchemaIncompatible { found, expected } ->
        if found == futureVersion && expected == Replay.Recording.currentSchemaVersion then
          Replay.Common.TestSuccess "validateSchemaVersion returns SchemaIncompatible for future version"
        else
          Replay.Common.TestFailure "validateSchemaVersion returns SchemaIncompatible for future version"
            ("Wrong found/expected: " <> show found <> "/" <> show expected)
      Replay.Recording.SchemaValid ->
        Replay.Common.TestFailure "validateSchemaVersion returns SchemaIncompatible for future version"
          "Returned SchemaValid for future version"

testMessageDirectionToHarnessRoundtrip :: Replay.Common.TestResult
testMessageDirectionToHarnessRoundtrip =
  let
    encoded = Data.Argonaut.Encode.encodeJson Replay.Recording.ToHarness
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right Replay.Recording.ToHarness ->
        Replay.Common.TestSuccess "MessageDirection ToHarness roundtrip"
      Data.Either.Right Replay.Recording.FromHarness ->
        Replay.Common.TestFailure "MessageDirection ToHarness roundtrip" "Decoded as FromHarness"
      Data.Either.Left err ->
        Replay.Common.TestFailure "MessageDirection ToHarness roundtrip" (Data.Argonaut.Decode.printJsonDecodeError err)

testMessageDirectionFromHarnessRoundtrip :: Replay.Common.TestResult
testMessageDirectionFromHarnessRoundtrip =
  let
    encoded = Data.Argonaut.Encode.encodeJson Replay.Recording.FromHarness
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right Replay.Recording.FromHarness ->
        Replay.Common.TestSuccess "MessageDirection FromHarness roundtrip"
      Data.Either.Right Replay.Recording.ToHarness ->
        Replay.Common.TestFailure "MessageDirection FromHarness roundtrip" "Decoded as ToHarness"
      Data.Either.Left err ->
        Replay.Common.TestFailure "MessageDirection FromHarness roundtrip" (Data.Argonaut.Decode.printJsonDecodeError err)

testMessageDirectionToHarnessSerializesToCorrectString :: Replay.Common.TestResult
testMessageDirectionToHarnessSerializesToCorrectString =
  let
    encoded = Data.Argonaut.Encode.encodeJson Replay.Recording.ToHarness
    expected = Data.Argonaut.Core.fromString "to_harness"
  in
    if encoded == expected then
      Replay.Common.TestSuccess "MessageDirection ToHarness serializes to 'to_harness'"
    else
      Replay.Common.TestFailure "MessageDirection ToHarness serializes to 'to_harness'"
        ("Expected 'to_harness', got " <> Data.Argonaut.Core.stringify encoded)

testMessageDirectionFromHarnessSerializesToCorrectString :: Replay.Common.TestResult
testMessageDirectionFromHarnessSerializesToCorrectString =
  let
    encoded = Data.Argonaut.Encode.encodeJson Replay.Recording.FromHarness
    expected = Data.Argonaut.Core.fromString "from_harness"
  in
    if encoded == expected then
      Replay.Common.TestSuccess "MessageDirection FromHarness serializes to 'from_harness'"
    else
      Replay.Common.TestFailure "MessageDirection FromHarness serializes to 'from_harness'"
        ("Expected 'from_harness', got " <> Data.Argonaut.Core.stringify encoded)

testEmptyRecordingHasCorrectSchemaVersion :: Replay.Common.TestResult
testEmptyRecordingHasCorrectSchemaVersion =
  let
    recording = Replay.Recording.emptyRecording "test-scenario" "2025-01-08T12:00:00.000Z"
  in
    if recording.schemaVersion == Replay.Recording.currentSchemaVersion then
      Replay.Common.TestSuccess "emptyRecording has correct schemaVersion"
    else
      Replay.Common.TestFailure "emptyRecording has correct schemaVersion"
        ("Expected " <> show Replay.Recording.currentSchemaVersion <> ", got " <> show recording.schemaVersion)

testEmptyRecordingHasCorrectScenarioName :: Replay.Common.TestResult
testEmptyRecordingHasCorrectScenarioName =
  let
    recording = Replay.Recording.emptyRecording "my-scenario" "2025-01-08T12:00:00.000Z"
  in
    if recording.scenarioName == "my-scenario" then
      Replay.Common.TestSuccess "emptyRecording has correct scenarioName"
    else
      Replay.Common.TestFailure "emptyRecording has correct scenarioName"
        ("Expected 'my-scenario', got " <> recording.scenarioName)

testEmptyRecordingHasCorrectTimestamp :: Replay.Common.TestResult
testEmptyRecordingHasCorrectTimestamp =
  let
    timestamp = "2025-01-08T12:00:00.000Z"
    recording = Replay.Recording.emptyRecording "test" timestamp
  in
    if recording.recordedAt == timestamp then
      Replay.Common.TestSuccess "emptyRecording has correct recordedAt timestamp"
    else
      Replay.Common.TestFailure "emptyRecording has correct recordedAt timestamp"
        ("Expected " <> timestamp <> ", got " <> recording.recordedAt)

testEmptyRecordingHasEmptyMessages :: Replay.Common.TestResult
testEmptyRecordingHasEmptyMessages =
  let
    recording = Replay.Recording.emptyRecording "test" "2025-01-08T12:00:00.000Z"
  in
    if Data.Array.null recording.messages then
      Replay.Common.TestSuccess "emptyRecording has empty messages array"
    else
      Replay.Common.TestFailure "emptyRecording has empty messages array"
        ("Expected empty array, got " <> show (Data.Array.length recording.messages) <> " messages")

makeTestEnvelope :: Replay.Recording.MessagePayload -> Replay.Protocol.Types.Envelope Replay.Recording.MessagePayload
makeTestEnvelope payload = Replay.Protocol.Types.Envelope
  { streamId: Replay.Protocol.Types.StreamId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  , traceId: Replay.Protocol.Types.TraceId "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  , causationStreamId: Json.Nullable.jsonNull
  , parentStreamId: Json.Nullable.jsonNull
  , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
  , eventSeq: Replay.Protocol.Types.EventSeq 0
  , timestamp: "2025-01-08T12:00:00.000Z"
  , channel: Replay.Protocol.Types.ProgramChannel
  , payloadHash: Data.Maybe.Nothing
  , payload
  }

makeTestMessage :: Replay.Recording.MessageDirection -> Replay.Recording.RecordedMessage
makeTestMessage direction =
  { envelope: makeTestEnvelope (Replay.Recording.PayloadCommand Replay.Protocol.Types.CommandClose)
  , recordedAt: "2025-01-08T12:00:01.000Z"
  , direction
  , hash: Data.Maybe.Nothing
  }

testAddMessageIncreasesCount :: Replay.Common.TestResult
testAddMessageIncreasesCount =
  let
    recording = Replay.Recording.emptyRecording "test" "2025-01-08T12:00:00.000Z"
    msg = makeTestMessage Replay.Recording.ToHarness
    updated = Replay.Recording.addMessage msg recording
  in
    if Data.Array.length updated.messages == 1 then
      Replay.Common.TestSuccess "addMessage increases message count"
    else
      Replay.Common.TestFailure "addMessage increases message count"
        ("Expected 1 message, got " <> show (Data.Array.length updated.messages))

testAddMessagePreservesOrder :: Replay.Common.TestResult
testAddMessagePreservesOrder =
  let
    recording = Replay.Recording.emptyRecording "test" "2025-01-08T12:00:00.000Z"
    msg1 = makeTestMessage Replay.Recording.ToHarness
    msg2 = makeTestMessage Replay.Recording.FromHarness
    updated = Replay.Recording.addMessage msg2 (Replay.Recording.addMessage msg1 recording)
  in
    case Data.Array.index updated.messages 0, Data.Array.index updated.messages 1 of
      Data.Maybe.Just m1, Data.Maybe.Just m2 ->
        if m1.direction == Replay.Recording.ToHarness && m2.direction == Replay.Recording.FromHarness then
          Replay.Common.TestSuccess "addMessage preserves message order"
        else
          Replay.Common.TestFailure "addMessage preserves message order" "Messages in wrong order"
      _, _ ->
        Replay.Common.TestFailure "addMessage preserves message order" "Could not access messages"

pureTests :: Array Replay.Common.TestResult
pureTests =
  [ testSchemaVersionValidCurrent
  , testSchemaVersionInvalidOld
  , testSchemaVersionInvalidFuture
  , testMessageDirectionToHarnessRoundtrip
  , testMessageDirectionFromHarnessRoundtrip
  , testMessageDirectionToHarnessSerializesToCorrectString
  , testMessageDirectionFromHarnessSerializesToCorrectString
  , testEmptyRecordingHasCorrectSchemaVersion
  , testEmptyRecordingHasCorrectScenarioName
  , testEmptyRecordingHasCorrectTimestamp
  , testEmptyRecordingHasEmptyMessages
  , testAddMessageIncreasesCount
  , testAddMessagePreservesOrder
  ]

testSaveAndLoadRoundtrip :: Effect.Aff.Aff Replay.Common.TestResult
testSaveAndLoadRoundtrip = do
  let testDir = "./replay-recording-test"
  let filepath = testDir <> "/roundtrip-test.json"
  let timestamp = "2025-01-08T12:00:00.000Z"
  let recording = Replay.Recording.emptyRecording "roundtrip-scenario" timestamp
  let msg = makeTestMessage Replay.Recording.ToHarness
  let recordingWithMsg = Replay.Recording.addMessage msg recording

  saveResult <- Replay.Recording.saveRecording filepath recordingWithMsg
  case saveResult of
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "save and load roundtrip" ("Save failed: " <> err)
    Data.Either.Right _ -> do
      loadResult <- Replay.Recording.loadRecording filepath
      case loadResult of
        Data.Either.Left err ->
          pure $ Replay.Common.TestFailure "save and load roundtrip" ("Load failed: " <> err)
        Data.Either.Right loaded ->
          if
            loaded.schemaVersion == recordingWithMsg.schemaVersion
              && loaded.scenarioName == recordingWithMsg.scenarioName
              && loaded.recordedAt == recordingWithMsg.recordedAt
              && Data.Array.length loaded.messages == Data.Array.length recordingWithMsg.messages then
            pure $ Replay.Common.TestSuccess "save and load roundtrip"
          else
            pure $ Replay.Common.TestFailure "save and load roundtrip" "Loaded recording differs from saved"

testLoadNonexistentFile :: Effect.Aff.Aff Replay.Common.TestResult
testLoadNonexistentFile = do
  let filepath = "./replay-recording-test/nonexistent-file-" <> "12345" <> ".json"
  result <- Replay.Recording.loadRecording filepath
  case result of
    Data.Either.Left _ ->
      pure $ Replay.Common.TestSuccess "loadRecording returns error for nonexistent file"
    Data.Either.Right _ ->
      pure $ Replay.Common.TestFailure "loadRecording returns error for nonexistent file"
        "Should have returned Left for nonexistent file"

testLoadInvalidJson :: Effect.Aff.Aff Replay.Common.TestResult
testLoadInvalidJson = do
  let testDir = "./replay-recording-test"
  let filepath = testDir <> "/invalid-json-test.json"
  _ <- Effect.Aff.attempt $ Node.FS.Aff.mkdir' testDir { mode: Node.FS.Perms.permsAll, recursive: true }
  _ <- Effect.Aff.attempt $ Node.FS.Aff.writeTextFile Node.Encoding.UTF8 filepath "{ not valid json"
  result <- Replay.Recording.loadRecording filepath
  case result of
    Data.Either.Left _ ->
      pure $ Replay.Common.TestSuccess "loadRecording returns error for invalid JSON"
    Data.Either.Right _ ->
      pure $ Replay.Common.TestFailure "loadRecording returns error for invalid JSON"
        "Should have returned Left for invalid JSON"

testLoadIncompatibleSchemaVersion :: Effect.Aff.Aff Replay.Common.TestResult
testLoadIncompatibleSchemaVersion = do
  let testDir = "./replay-recording-test"
  let filepath = testDir <> "/incompatible-version-test.json"
  let invalidVersionJson = """{"schemaVersion":999,"scenarioName":"test","recordedAt":"2025-01-08T12:00:00.000Z","messages":[]}"""
  _ <- Effect.Aff.attempt $ Node.FS.Aff.mkdir' testDir { mode: Node.FS.Perms.permsAll, recursive: true }
  _ <- Effect.Aff.attempt $ Node.FS.Aff.writeTextFile Node.Encoding.UTF8 filepath invalidVersionJson
  result <- Replay.Recording.loadRecording filepath
  case result of
    Data.Either.Left err ->
      if Data.String.contains (Data.String.Pattern "Incompatible schema version") err then
        pure $ Replay.Common.TestSuccess "loadRecording returns error for incompatible schema version"
      else
        pure $ Replay.Common.TestFailure "loadRecording returns error for incompatible schema version"
          ("Expected schema version error, got: " <> err)
    Data.Either.Right _ ->
      pure $ Replay.Common.TestFailure "loadRecording returns error for incompatible schema version"
        "Should have returned Left for incompatible schema version"

testSaveCreatesDirectory :: Effect.Aff.Aff Replay.Common.TestResult
testSaveCreatesDirectory = do
  let testDir = "./replay-recording-test/nested/deep/dir"
  let filepath = testDir <> "/auto-created.json"
  let recording = Replay.Recording.emptyRecording "test" "2025-01-08T12:00:00.000Z"
  _ <- Effect.Aff.attempt $ Node.FS.Aff.rm' "./replay-recording-test/nested" { force: true, recursive: true, maxRetries: 0, retryDelay: 0 }
  result <- Replay.Recording.saveRecording filepath recording
  case result of
    Data.Either.Left err ->
      pure $ Replay.Common.TestFailure "saveRecording creates nested directories" ("Save failed: " <> err)
    Data.Either.Right _ -> do
      loadResult <- Replay.Recording.loadRecording filepath
      case loadResult of
        Data.Either.Left err ->
          pure $ Replay.Common.TestFailure "saveRecording creates nested directories" ("File not readable after save: " <> err)
        Data.Either.Right _ ->
          pure $ Replay.Common.TestSuccess "saveRecording creates nested directories"

affTests :: Effect.Aff.Aff (Array Replay.Common.TestResult)
affTests = do
  r1 <- testSaveAndLoadRoundtrip
  r2 <- testLoadNonexistentFile
  r3 <- testLoadInvalidJson
  r4 <- testLoadIncompatibleSchemaVersion
  r5 <- testSaveCreatesDirectory
  pure [ r1, r2, r3, r4, r5 ]

runTests :: Effect.Aff.Aff Replay.Common.TestResults
runTests = do
  affResults <- affTests
  let allResults = pureTests <> affResults
  pure $ Replay.Common.computeResults allResults
