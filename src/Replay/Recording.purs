module Replay.Recording
  ( Recording
  , RecordedMessage
  , module Replay.Protocol.Types
  , MessagePayload(..)
  , currentSchemaVersion
  , emptyRecording
  , addMessage
  , loadRecording
  , saveRecording
  , validateSchemaVersion
  , SchemaValidationResult(..)
  , buildHashIndex
  , HashIndex
  , toCompressedPath
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Decode (class DecodeJson, (.:), (.:?))
import Data.Argonaut.Decode.Error as Data.Argonaut.Decode.Error
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Argonaut.Encode (class EncodeJson, (:=), (~>))
import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Map as Data.Map
import Data.Maybe as Data.Maybe
import Data.String as Data.String
import Data.Traversable as Data.Traversable
import Data.Tuple as Data.Tuple
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import FFI.Buffer as FFI.Buffer
import FFI.Zstd as FFI.Zstd
import Node.Buffer as Node.Buffer
import Node.Encoding as Node.Encoding
import Node.FS.Aff as Node.FS.Aff
import Node.FS.Perms as Node.FS.Perms
import Node.Path as Node.Path
import Replay.Protocol.Types as Replay.Protocol.Types

-- ============================================================================
-- Schema Version
-- ============================================================================

currentSchemaVersion :: Int
currentSchemaVersion = 2

data SchemaValidationResult
  = SchemaValid
  | SchemaIncompatible { found :: Int, expected :: Int }

derive instance Eq SchemaValidationResult

instance Show SchemaValidationResult where
  show SchemaValid = "SchemaValid"
  show (SchemaIncompatible { found, expected }) =
    "SchemaIncompatible { found: " <> show found <> ", expected: " <> show expected <> " }"

validateSchemaVersion :: Int -> SchemaValidationResult
validateSchemaVersion version =
  if version >= 1 && version <= currentSchemaVersion then
    SchemaValid
  else
    SchemaIncompatible { found: version, expected: currentSchemaVersion }

-- ============================================================================
-- Recorded Message
-- ============================================================================

type RecordedMessage =
  { envelope :: Replay.Protocol.Types.Envelope MessagePayload
  , recordedAt :: String
  , direction :: Replay.Protocol.Types.MessageDirection
  , hash :: Data.Maybe.Maybe String
  }

-- | The payload type for recorded messages - either a Command (app -> harness) or Event (harness -> app)
data MessagePayload
  = PayloadCommand Replay.Protocol.Types.Command
  | PayloadEvent Replay.Protocol.Types.Event

instance Show MessagePayload where
  show (PayloadCommand cmd) = "PayloadCommand " <> show cmd
  show (PayloadEvent evt) = "PayloadEvent " <> show evt

instance EncodeJson MessagePayload where
  encodeJson (PayloadCommand cmd) =
    "kind" := ("command" :: String)
      ~> "data" := cmd
      ~> Data.Argonaut.Core.jsonEmptyObject
  encodeJson (PayloadEvent evt) =
    "kind" := ("event" :: String)
      ~> "data" := evt
      ~> Data.Argonaut.Core.jsonEmptyObject

instance DecodeJson MessagePayload where
  decodeJson json = do
    obj <- Data.Argonaut.Decode.decodeJson json
    kind :: String <- obj .: "kind"
    case kind of
      "command" -> do
        cmd <- obj .: "data"
        Data.Either.Right $ PayloadCommand cmd
      "event" -> do
        evt <- obj .: "data"
        Data.Either.Right $ PayloadEvent evt
      other ->
        Data.Either.Left (Data.Argonaut.Decode.Error.TypeMismatch ("Unknown message payload kind: " <> other))

-- ============================================================================
-- Recording
-- ============================================================================

type Recording =
  { schemaVersion :: Int
  , scenarioName :: String
  , recordedAt :: String
  , messages :: Array RecordedMessage
  }

emptyRecording :: String -> String -> Recording
emptyRecording scenarioName timestamp =
  { schemaVersion: currentSchemaVersion
  , scenarioName
  , recordedAt: timestamp
  , messages: []
  }

addMessage :: RecordedMessage -> Recording -> Recording
addMessage message recording =
  recording { messages = Data.Array.snoc recording.messages message }

-- ============================================================================
-- JSON Encoding/Decoding for Recording
-- ============================================================================

encodeRecordedMessage :: RecordedMessage -> Data.Argonaut.Core.Json
encodeRecordedMessage msg =
  "envelope" := msg.envelope
    ~> "recordedAt" := msg.recordedAt
    ~> "direction" := msg.direction
    ~> "hash" := msg.hash
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeRecordedMessage :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError RecordedMessage
decodeRecordedMessage json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  envelope <- obj .: "envelope"
  recordedAt <- obj .: "recordedAt"
  direction <- obj .: "direction"
  hashField <- obj .:? "hash"
  Data.Either.Right { envelope, recordedAt, direction, hash: Data.Maybe.fromMaybe Data.Maybe.Nothing hashField }

encodeRecording :: Recording -> Data.Argonaut.Core.Json
encodeRecording recording =
  "schemaVersion" := recording.schemaVersion
    ~> "scenarioName" := recording.scenarioName
    ~> "recordedAt" := recording.recordedAt
    ~> "messages" := map encodeRecordedMessage recording.messages
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeRecording :: Data.Argonaut.Core.Json -> Data.Either.Either Data.Argonaut.Decode.Error.JsonDecodeError Recording
decodeRecording json = do
  obj <- Data.Argonaut.Decode.decodeJson json
  schemaVersion <- obj .: "schemaVersion"
  scenarioName <- obj .: "scenarioName"
  recordedAt <- obj .: "recordedAt"
  messagesJson :: Array Data.Argonaut.Core.Json <- obj .: "messages"
  messages <- Data.Traversable.traverse decodeRecordedMessage messagesJson
  Data.Either.Right { schemaVersion, scenarioName, recordedAt, messages }

-- ============================================================================
-- File Operations
-- ============================================================================

mkdirRecursive :: String -> Effect.Aff.Aff Unit
mkdirRecursive path = Node.FS.Aff.mkdir' path { mode: Node.FS.Perms.permsAll, recursive: true }

toCompressedPath :: String -> String
toCompressedPath path =
  case Data.String.stripSuffix (Data.String.Pattern ".json") path of
    Data.Maybe.Just base -> base <> ".json.zstd"
    Data.Maybe.Nothing -> path <> ".zstd"

-- | Check if a path ends with .json.zstd
isCompressedPath :: String -> Boolean
isCompressedPath path = Data.Maybe.isJust $ Data.String.stripSuffix (Data.String.Pattern ".json.zstd") path

-- | Check if a file exists
fileExists :: String -> Effect.Aff.Aff Boolean
fileExists path = do
  result <- Effect.Aff.attempt $ Node.FS.Aff.stat path
  pure $ Data.Either.isRight result

-- | Load and decompress a .json.zstd file
loadCompressedContent :: String -> Effect.Aff.Aff (Data.Either.Either String String)
loadCompressedContent filepath = do
  result <- Effect.Aff.attempt $ Node.FS.Aff.readFile filepath
  case result of
    Data.Either.Left err ->
      pure $ Data.Either.Left $ "Could not read compressed file: " <> filepath <> "\nError: " <> show err
    Data.Either.Right compressedBuffer -> do
      decompressResult <- Effect.Aff.attempt $ FFI.Zstd.decompress compressedBuffer
      case decompressResult of
        Data.Either.Left err ->
          pure $ Data.Either.Left $ "Could not decompress file: " <> filepath <> "\nError: " <> show err
        Data.Either.Right decompressedBuffer -> do
          content <- Effect.Class.liftEffect $ FFI.Buffer.toString "utf8" decompressedBuffer
          pure $ Data.Either.Right content

-- | Load a recording from file path
-- | Automatically detects and handles both .json and .json.zstd formats
-- | Priority: .json.zstd > .json (compressed format preferred)
loadRecording :: String -> Effect.Aff.Aff (Data.Either.Either String Recording)
loadRecording filepath = do
  -- Determine paths to try
  let
    compressedPath = toCompressedPath filepath
    uncompressedPath = filepath
    -- If the provided path is already compressed, don't try to add extension
    pathsToTry =
      if isCompressedPath filepath then
        [ filepath ]
      else
        [ compressedPath, uncompressedPath ]

  -- Try compressed format first, then fall back to uncompressed
  tryLoadPaths pathsToTry
  where
  tryLoadPaths :: Array String -> Effect.Aff.Aff (Data.Either.Either String Recording)
  tryLoadPaths paths =
    case Data.Array.uncons paths of
      Data.Maybe.Nothing ->
        pure $ Data.Either.Left $ "No recording file found at: " <> filepath
      Data.Maybe.Just { head: path, tail: remainingPaths } -> do
        exists <- fileExists path
        if exists then do
          contentResult <-
            if isCompressedPath path then
              loadCompressedContent path
            else do
              result <- Effect.Aff.attempt $ Node.FS.Aff.readTextFile Node.Encoding.UTF8 path
              case result of
                Data.Either.Left err ->
                  pure $ Data.Either.Left $ "Could not read file: " <> path <> "\nError: " <> show err
                Data.Either.Right content ->
                  pure $ Data.Either.Right content
          case contentResult of
            Data.Either.Left err ->
              -- Try next path if this one failed
              if Data.Array.null remainingPaths then
                pure $ Data.Either.Left err
              else
                tryLoadPaths remainingPaths
            Data.Either.Right content ->
              parseRecordingContent path content
        else
          tryLoadPaths remainingPaths

  parseRecordingContent :: String -> String -> Effect.Aff.Aff (Data.Either.Either String Recording)
  parseRecordingContent path content =
    case Data.Argonaut.Decode.parseJson content of
      Data.Either.Left parseErr ->
        pure $ Data.Either.Left $ "Invalid JSON in " <> path <> "\nError: " <> show parseErr
      Data.Either.Right json ->
        case decodeRecording json of
          Data.Either.Left decodeErr ->
            pure $ Data.Either.Left $ "Could not decode recording from " <> path <> "\nError: " <> Data.Argonaut.Decode.printJsonDecodeError decodeErr
          Data.Either.Right recording ->
            case validateSchemaVersion recording.schemaVersion of
              SchemaValid ->
                pure $ Data.Either.Right recording
              SchemaIncompatible { found, expected } ->
                pure $ Data.Either.Left $ "Incompatible schema version in " <> path <> ". Found version " <> show found <> ", expected version " <> show expected

-- | Save a recording to a file path
-- | Always writes compressed .json.zstd format
-- | If the provided path ends in .json, it will be converted to .json.zstd
saveRecording :: String -> Recording -> Effect.Aff.Aff (Data.Either.Either String Unit)
saveRecording filepath recording = do
  -- Always use compressed path
  let
    outputPath =
      if isCompressedPath filepath then
        filepath
      else
        toCompressedPath filepath
    dirPath = Node.Path.dirname outputPath

  dirResult <- Effect.Aff.attempt $ mkdirRecursive dirPath
  case dirResult of
    Data.Either.Left err ->
      pure $ Data.Either.Left $ "Could not create directory: " <> dirPath <> "\nError: " <> show err
    Data.Either.Right _ -> do
      -- Encode to JSON string
      let json = encodeRecording recording
      let content = Data.Argonaut.Core.stringifyWithIndent 2 json <> "\n"

      -- Convert to buffer and compress
      contentBuffer <- Effect.Class.liftEffect $ FFI.Buffer.fromString content "utf8"
      compressResult <- Effect.Aff.attempt $ FFI.Zstd.compress contentBuffer
      case compressResult of
        Data.Either.Left err ->
          pure $ Data.Either.Left $ "Could not compress recording: " <> show err
        Data.Either.Right compressedBuffer -> do
          writeResult <- Effect.Aff.attempt $ Node.FS.Aff.writeFile outputPath compressedBuffer
          case writeResult of
            Data.Either.Left err ->
              pure $ Data.Either.Left $ "Could not write file: " <> outputPath <> "\nError: " <> show err
            Data.Either.Right _ ->
              pure $ Data.Either.Right unit

-- ============================================================================
-- Hash Index for O(1) Lookup
-- ============================================================================

type HashIndex = Data.Map.Map String (Array { index :: Int, message :: RecordedMessage })

buildHashIndex :: Recording -> HashIndex
buildHashIndex recording =
  let
    indexedMessages = Data.Array.mapWithIndex (\idx msg -> Data.Tuple.Tuple idx msg) recording.messages
    toHashEntries = Data.Array.mapMaybe toHashEntry indexedMessages
  in
    Data.Array.foldr insertEntry Data.Map.empty toHashEntries
  where
  toHashEntry :: Data.Tuple.Tuple Int RecordedMessage -> Data.Maybe.Maybe (Data.Tuple.Tuple String { index :: Int, message :: RecordedMessage })
  toHashEntry (Data.Tuple.Tuple idx msg) =
    case msg.hash of
      Data.Maybe.Just h -> Data.Maybe.Just $ Data.Tuple.Tuple h { index: idx, message: msg }
      Data.Maybe.Nothing -> Data.Maybe.Nothing

  insertEntry :: Data.Tuple.Tuple String { index :: Int, message :: RecordedMessage } -> HashIndex -> HashIndex
  insertEntry (Data.Tuple.Tuple hashKey entry) hashMap =
    let
      existing = Data.Maybe.fromMaybe [] (Data.Map.lookup hashKey hashMap)
    in
      Data.Map.insert hashKey (Data.Array.snoc existing entry) hashMap
