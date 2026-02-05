module Replay.Hash
  ( PayloadHash(..)
  , computePayloadHash
  , hashLookupKey
  , getHashNormalize
  ) where

import Prelude

import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Maybe as Data.Maybe
import Data.Newtype as Data.Newtype
import Data.String as Data.String
import Effect as Effect
import Effect.Exception as Effect.Exception
import FFI.Crypto as FFI.Crypto
import Node.Process as Node.Process
import Replay.Protocol.Types as Replay.Protocol.Types

newtype PayloadHash = PayloadHash String

derive instance Data.Newtype.Newtype PayloadHash _
derive instance Eq PayloadHash
derive instance Ord PayloadHash
derive newtype instance Show PayloadHash

instance Data.Argonaut.Encode.EncodeJson PayloadHash where
  encodeJson (PayloadHash h) = Data.Argonaut.Encode.encodeJson h

instance Data.Argonaut.Decode.DecodeJson PayloadHash where
  decodeJson json = PayloadHash <$> Data.Argonaut.Decode.decodeJson json

hashLookupKey :: PayloadHash -> String
hashLookupKey (PayloadHash h) = h

computePayloadHash :: Replay.Protocol.Types.RequestPayload -> Effect.Effect PayloadHash
computePayloadHash payload = do
  let normalizedJson = Data.Argonaut.Encode.encodeJson payload
  canonicalStr <- FFI.Crypto.canonicalJsonStringify normalizedJson
  hashStr <- FFI.Crypto.sha256Hash canonicalStr
  pure $ PayloadHash hashStr

-- | Read REPLAY_HASH_NORMALIZE environment variable to determine if payload
-- | normalization should be applied before hashing.
-- | Default: true (normalize). Set to "false" or "0" to hash full payloads.
-- | Valid values: "true", "false", "1", "0" (case-insensitive for true/false).
-- | Throws on invalid values.
getHashNormalize :: Effect.Effect Boolean
getHashNormalize = do
  maybeVal <- Node.Process.lookupEnv "REPLAY_HASH_NORMALIZE"
  case maybeVal of
    Data.Maybe.Nothing ->
      pure true
    Data.Maybe.Just val ->
      case Data.String.toLower val of
        "true" ->
          pure true
        "1" ->
          pure true
        "false" ->
          pure false
        "0" ->
          pure false
        _ ->
          Effect.Exception.throw $
            "Invalid REPLAY_HASH_NORMALIZE value: \"" <> val <> "\". Valid values: true, false, 1, 0"
