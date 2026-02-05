-- | JSON-nullable wrapper with Argonaut instances
-- |
-- | This module provides JsonNullable, a newtype around Nullable
-- | that has EncodeJson/DecodeJson instances. This avoids orphan instances.
-- |
-- | Encoding:
-- |   JsonNullable Nullable.null -> JSON null
-- |   JsonNullable (Nullable.notNull x) -> encoded value of x
-- |
-- | Decoding:
-- |   JSON null -> JsonNullable Nullable.null
-- |   other -> JsonNullable (Nullable.notNull (decode other))
module Json.Nullable
  ( JsonNullable(..)
  , fromJsonNullable
  , jsonNull
  , jsonNotNull
  , maybeToJsonNullable
  , jsonNullableToMaybe
  ) where

import Prelude
import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Decode.Class as Data.Argonaut.Decode.Class
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Argonaut.Encode.Class as Data.Argonaut.Encode.Class
import Data.Either as Data.Either
import Data.Maybe as Data.Maybe
import Data.Nullable as Data.Nullable

-- | Newtype wrapper for Nullable with Argonaut instances
newtype JsonNullable a = JsonNullable (Data.Nullable.Nullable a)

instance Eq a => Eq (JsonNullable a) where
  eq (JsonNullable a) (JsonNullable b) =
    case Data.Nullable.toMaybe a, Data.Nullable.toMaybe b of
      Data.Maybe.Nothing, Data.Maybe.Nothing -> true
      Data.Maybe.Just x, Data.Maybe.Just y -> x == y
      _, _ -> false

-- | Unwrap JsonNullable to Nullable
fromJsonNullable :: forall a. JsonNullable a -> Data.Nullable.Nullable a
fromJsonNullable (JsonNullable n) = n

-- | Create a null JsonNullable
jsonNull :: forall a. JsonNullable a
jsonNull = JsonNullable Data.Nullable.null

-- | Create a non-null JsonNullable
jsonNotNull :: forall a. a -> JsonNullable a
jsonNotNull = JsonNullable <<< Data.Nullable.notNull

-- | Encode JsonNullable to JSON
instance (Data.Argonaut.Encode.Class.EncodeJson a) => Data.Argonaut.Encode.Class.EncodeJson (JsonNullable a) where
  encodeJson (JsonNullable nullable) =
    case Data.Nullable.toMaybe nullable of
      Data.Maybe.Nothing -> Data.Argonaut.Core.jsonNull
      Data.Maybe.Just a -> Data.Argonaut.Encode.encodeJson a

-- | Decode JsonNullable from JSON
instance (Data.Argonaut.Decode.Class.DecodeJson a) => Data.Argonaut.Decode.Class.DecodeJson (JsonNullable a) where
  decodeJson json =
    if Data.Argonaut.Core.isNull json then
      Data.Either.Right (JsonNullable Data.Nullable.null)
    else
      map (JsonNullable <<< Data.Nullable.notNull) (Data.Argonaut.Decode.decodeJson json)

-- | Convert Maybe to JsonNullable
maybeToJsonNullable :: forall a. Data.Maybe.Maybe a -> JsonNullable a
maybeToJsonNullable = case _ of
  Data.Maybe.Nothing -> jsonNull
  Data.Maybe.Just a -> jsonNotNull a

-- | Convert JsonNullable to Maybe
jsonNullableToMaybe :: forall a. JsonNullable a -> Data.Maybe.Maybe a
jsonNullableToMaybe = Data.Nullable.toMaybe <<< fromJsonNullable
