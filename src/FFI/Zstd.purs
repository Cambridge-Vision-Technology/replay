module FFI.Zstd
  ( compress
  , decompress
  ) where

import Prelude

import Control.Promise as Control.Promise
import Effect as Effect
import Effect.Aff as Effect.Aff
import Node.Buffer as Node.Buffer

foreign import compressImpl
  :: Node.Buffer.Buffer
  -> Effect.Effect (Control.Promise.Promise Node.Buffer.Buffer)

foreign import decompressImpl
  :: Node.Buffer.Buffer
  -> Effect.Effect (Control.Promise.Promise Node.Buffer.Buffer)

compress :: Node.Buffer.Buffer -> Effect.Aff.Aff Node.Buffer.Buffer
compress buffer =
  Control.Promise.toAffE (compressImpl buffer)

decompress :: Node.Buffer.Buffer -> Effect.Aff.Aff Node.Buffer.Buffer
decompress buffer =
  Control.Promise.toAffE (decompressImpl buffer)
