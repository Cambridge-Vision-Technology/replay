module Replay.Time
  ( getCurrentTimestamp
  , formatTimestamp
  ) where

import Prelude

import Data.DateTime.Instant as Data.DateTime.Instant
import Data.Either as Data.Either
import Data.Formatter.DateTime as Data.Formatter.DateTime
import Effect as Effect
import Effect.Now as Effect.Now

getCurrentTimestamp :: Effect.Effect String
getCurrentTimestamp = do
  now <- Effect.Now.now
  pure $ formatTimestamp now

formatTimestamp :: Data.DateTime.Instant.Instant -> String
formatTimestamp instant =
  case Data.DateTime.Instant.toDateTime instant of
    dateTime ->
      Data.Formatter.DateTime.format iso8601Format dateTime

iso8601Format :: Data.Formatter.DateTime.Formatter
iso8601Format = Data.Either.either (const mempty) identity
  $ Data.Formatter.DateTime.parseFormatString "YYYY-MM-DDTHH:mm:ss.SSSZ"
