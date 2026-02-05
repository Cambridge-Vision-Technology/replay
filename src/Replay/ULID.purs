module Replay.ULID
  ( ULID(..)
  , Timestamp(..)
  , generate
  , generateAt
  , parse
  , fromString
  , timestamp
  , toString
  ) where

import Prelude

import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Decode (class DecodeJson)
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Argonaut.Encode (class EncodeJson)
import Data.Either as Data.Either
import Data.Maybe as Data.Maybe
import Data.Newtype as Data.Newtype
import Data.String as Data.String
import Data.String.Regex as Data.String.Regex
import Data.String.Regex.Flags as Data.String.Regex.Flags
import Effect as Effect
import Effect.Uncurried as Effect.Uncurried

newtype ULID = ULID String

derive instance Data.Newtype.Newtype ULID _
derive instance Eq ULID
derive instance Ord ULID

instance Show ULID where
  show (ULID s) = "(ULID " <> s <> ")"

instance EncodeJson ULID where
  encodeJson (ULID s) = Data.Argonaut.Encode.encodeJson s

instance DecodeJson ULID where
  decodeJson json = do
    str <- Data.Argonaut.Decode.decodeJson json
    case parse str of
      Data.Either.Left err -> Data.Either.Left (Data.Argonaut.Decode.TypeMismatch err)
      Data.Either.Right ulid -> Data.Either.Right ulid

newtype Timestamp = Timestamp Number

derive instance Data.Newtype.Newtype Timestamp _
derive instance Eq Timestamp
derive instance Ord Timestamp

instance Show Timestamp where
  show (Timestamp n) = "(Timestamp " <> show n <> ")"

instance EncodeJson Timestamp where
  encodeJson (Timestamp n) = Data.Argonaut.Encode.encodeJson n

instance DecodeJson Timestamp where
  decodeJson json = Timestamp <$> Data.Argonaut.Decode.decodeJson json

foreign import generateImpl :: Effect.Effect String

foreign import generateAtImpl :: Effect.Uncurried.EffectFn1 Number String

foreign import decodeTimeImpl :: Effect.Uncurried.EffectFn1 String Number

generate :: Effect.Effect ULID
generate = ULID <$> generateImpl

generateAt :: Timestamp -> Effect.Effect ULID
generateAt (Timestamp ms) = ULID <$> Effect.Uncurried.runEffectFn1 generateAtImpl ms

ulidPatternString :: String
ulidPatternString = "^[0-9A-HJKMNP-TV-Z]{26}$"

matchesUlidPattern :: String -> Boolean
matchesUlidPattern str =
  case Data.String.Regex.regex ulidPatternString Data.String.Regex.Flags.noFlags of
    Data.Either.Left _ -> false
    Data.Either.Right pattern -> Data.String.Regex.test pattern str

isValidULID :: String -> Boolean
isValidULID str =
  Data.String.length str == 26
    && matchesUlidPattern (Data.String.toUpper str)

parse :: String -> Data.Either.Either String ULID
parse str =
  let
    upper = Data.String.toUpper str
  in
    if isValidULID upper then
      Data.Either.Right (ULID upper)
    else
      Data.Either.Left ("Invalid ULID format: " <> str <> ". Expected 26 characters matching Crockford Base32 alphabet.")

fromString :: String -> Data.Maybe.Maybe ULID
fromString str = Data.Either.hush (parse str)

timestamp :: ULID -> Effect.Effect Timestamp
timestamp (ULID str) = Timestamp <$> Effect.Uncurried.runEffectFn1 decodeTimeImpl str

toString :: ULID -> String
toString (ULID str) = str
