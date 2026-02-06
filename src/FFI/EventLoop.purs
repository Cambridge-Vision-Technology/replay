module FFI.EventLoop
  ( buildHashIndexChunkedAff
  , RawHashIndex
  ) where

import Prelude

import Control.Promise as Control.Promise
import Data.Argonaut.Core as Data.Argonaut.Core
import Effect as Effect
import Effect.Aff as Effect.Aff
import Foreign.Object as Foreign.Object

-- | Raw hash index type from JavaScript.
-- | This is a plain JavaScript object where:
-- | - Keys are hash strings
-- | - Values are arrays of {index, message} objects
-- |
-- | We use Foreign.Object to represent this on the PureScript side,
-- | as it maps directly to JavaScript objects.
type RawHashIndex = Foreign.Object.Object (Array { index :: Int, message :: Data.Argonaut.Core.Json })

-- | Foreign import for building a hash index in chunks.
-- | Takes a chunk size and array of raw JSON messages, returns Promise of hash index.
foreign import buildHashIndexChunkedImpl
  :: Int
  -> Array Data.Argonaut.Core.Json
  -> Effect.Effect (Control.Promise.Promise RawHashIndex)

-- | Build a hash index from an array of raw JSON messages in chunks (Aff version).
-- | This is a convenience wrapper for PureScript async workflows.
buildHashIndexChunkedAff
  :: Int
  -> Array Data.Argonaut.Core.Json
  -> Effect.Aff.Aff RawHashIndex
buildHashIndexChunkedAff chunkSize messages =
  Control.Promise.toAffE (buildHashIndexChunkedImpl chunkSize messages)
