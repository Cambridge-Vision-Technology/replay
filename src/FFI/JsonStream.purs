module FFI.JsonStream
  ( parseArrayStream
  , parseRecordingStreamAff
  , StreamedRecording
  ) where

import Control.Promise as Control.Promise
import Data.Argonaut.Core as Data.Argonaut.Core
import Effect as Effect
import Effect.Aff as Effect.Aff
import Node.Buffer as Node.Buffer

-- | Foreign import for the streaming JSON array parser.
-- | Takes a Buffer containing JSON array data and returns a Promise
-- | that resolves to an array of JSON values.
foreign import parseArrayStreamImpl
  :: Node.Buffer.Buffer
  -> Effect.Effect (Control.Promise.Promise (Array Data.Argonaut.Core.Json))

-- | Parse a JSON array from a Buffer without blocking the event loop.
-- | Returns an Effect that produces a Promise - matches the JavaScript FFI pattern.
-- |
-- | The parser processes the array in chunks, yielding control to the
-- | event loop periodically to allow other callbacks to run.
-- |
-- | This is useful for parsing large JSON files (e.g., 50MB+) where
-- | synchronous parsing would block the event loop and cause timeouts.
-- |
-- | Note: This function is exported for JavaScript test use
-- | (features/step_definitions/streaming_json_steps.js).
-- | PureScript code should use parseRecordingStreamAff instead.
-- |
-- | Usage from JavaScript:
-- |   const result = await parseArrayStream(buffer)();
parseArrayStream
  :: Node.Buffer.Buffer
  -> Effect.Effect (Control.Promise.Promise (Array Data.Argonaut.Core.Json))
parseArrayStream = parseArrayStreamImpl

-- ============================================================================
-- Streaming Recording Parser
-- ============================================================================

-- | Type alias for the streaming recording result from JavaScript.
-- | Contains the metadata fields and the raw JSON messages array.
type StreamedRecording =
  { schemaVersion :: Int
  , scenarioName :: String
  , recordedAt :: String
  , messages :: Array Data.Argonaut.Core.Json
  }

-- | Foreign import for the streaming recording parser.
-- | Takes a Buffer containing recording JSON data and returns a Promise
-- | that resolves to a StreamedRecording with parsed metadata and raw messages.
foreign import parseRecordingStreamImpl
  :: Node.Buffer.Buffer
  -> Effect.Effect (Control.Promise.Promise StreamedRecording)

-- | Parse a recording JSON from a Buffer without blocking the event loop.
-- | Returns an Aff for PureScript async workflows.
-- |
-- | This is a convenience wrapper for PureScript code that wants to use
-- | the streaming recording parser within Aff contexts.
parseRecordingStreamAff :: Node.Buffer.Buffer -> Effect.Aff.Aff StreamedRecording
parseRecordingStreamAff buffer =
  Control.Promise.toAffE (parseRecordingStreamImpl buffer)
