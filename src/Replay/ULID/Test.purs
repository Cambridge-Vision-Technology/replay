module Replay.ULID.Test
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
import Data.String.Regex as Data.String.Regex
import Data.String.Regex.Flags as Data.String.Regex.Flags
import Effect as Effect
import Replay.Common as Replay.Common
import Replay.ULID as Replay.ULID

runPureTest :: String -> (Unit -> Replay.Common.TestResult) -> Replay.Common.TestResult
runPureTest name test = test unit

testGenerateProducesValidFormat :: Effect.Effect Replay.Common.TestResult
testGenerateProducesValidFormat = do
  ulid <- Replay.ULID.generate
  let str = Replay.ULID.toString ulid
  let lengthOk = Data.String.length str == 26
  let patternOk = matchesCrockfordBase32 str
  pure $
    if lengthOk && patternOk then
      Replay.Common.TestSuccess "generate produces valid 26-character ULID"
    else
      Replay.Common.TestFailure "generate produces valid 26-character ULID"
        ("Got: " <> str <> ", length: " <> show (Data.String.length str) <> ", pattern match: " <> show patternOk)

testGenerateAtProducesValidFormat :: Effect.Effect Replay.Common.TestResult
testGenerateAtProducesValidFormat = do
  let timestamp = Replay.ULID.Timestamp 1704067200000.0
  ulid <- Replay.ULID.generateAt timestamp
  let str = Replay.ULID.toString ulid
  let lengthOk = Data.String.length str == 26
  let patternOk = matchesCrockfordBase32 str
  pure $
    if lengthOk && patternOk then
      Replay.Common.TestSuccess "generateAt produces valid 26-character ULID"
    else
      Replay.Common.TestFailure "generateAt produces valid 26-character ULID"
        ("Got: " <> str <> ", length: " <> show (Data.String.length str) <> ", pattern match: " <> show patternOk)

testGenerateProducesUniqueValues :: Effect.Effect Replay.Common.TestResult
testGenerateProducesUniqueValues = do
  ulid1 <- Replay.ULID.generate
  ulid2 <- Replay.ULID.generate
  ulid3 <- Replay.ULID.generate
  let str1 = Replay.ULID.toString ulid1
  let str2 = Replay.ULID.toString ulid2
  let str3 = Replay.ULID.toString ulid3
  let allDifferent = str1 /= str2 && str2 /= str3 && str1 /= str3
  pure $
    if allDifferent then
      Replay.Common.TestSuccess "generate produces unique values"
    else
      Replay.Common.TestFailure "generate produces unique values"
        ("Got duplicates: " <> str1 <> ", " <> str2 <> ", " <> str3)

testParseAcceptsValidULID :: Replay.Common.TestResult
testParseAcceptsValidULID =
  let
    validULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
    result = Replay.ULID.parse validULID
  in
    case result of
      Data.Either.Right ulid ->
        if Replay.ULID.toString ulid == validULID then
          Replay.Common.TestSuccess "parse accepts valid ULID"
        else
          Replay.Common.TestFailure "parse accepts valid ULID" ("String mismatch: " <> Replay.ULID.toString ulid)
      Data.Either.Left err ->
        Replay.Common.TestFailure "parse accepts valid ULID" err

testParseAcceptsLowercaseULID :: Replay.Common.TestResult
testParseAcceptsLowercaseULID =
  let
    lowercaseULID = "01arz3ndektsv4rrffq69g5fav"
    result = Replay.ULID.parse lowercaseULID
  in
    case result of
      Data.Either.Right ulid ->
        if Replay.ULID.toString ulid == "01ARZ3NDEKTSV4RRFFQ69G5FAV" then
          Replay.Common.TestSuccess "parse accepts lowercase and normalizes to uppercase"
        else
          Replay.Common.TestFailure "parse accepts lowercase and normalizes to uppercase" ("Got: " <> Replay.ULID.toString ulid)
      Data.Either.Left err ->
        Replay.Common.TestFailure "parse accepts lowercase and normalizes to uppercase" err

testParseRejectsTooShort :: Replay.Common.TestResult
testParseRejectsTooShort =
  let
    shortULID = "01ARZ3NDEKTSV4RRFFQ69G5FA"
    result = Replay.ULID.parse shortULID
  in
    case result of
      Data.Either.Left _ -> Replay.Common.TestSuccess "parse rejects too short input"
      Data.Either.Right _ -> Replay.Common.TestFailure "parse rejects too short input" "Should have rejected 25-char string"

testParseRejectsTooLong :: Replay.Common.TestResult
testParseRejectsTooLong =
  let
    longULID = "01ARZ3NDEKTSV4RRFFQ69G5FAVX"
    result = Replay.ULID.parse longULID
  in
    case result of
      Data.Either.Left _ -> Replay.Common.TestSuccess "parse rejects too long input"
      Data.Either.Right _ -> Replay.Common.TestFailure "parse rejects too long input" "Should have rejected 27-char string"

testParseRejectsInvalidCharacters :: Replay.Common.TestResult
testParseRejectsInvalidCharacters =
  let
    invalidULID = "01ARZ3NDEKTSV4RRFFQ69G5FIL"
    result = Replay.ULID.parse invalidULID
  in
    case result of
      Data.Either.Left _ -> Replay.Common.TestSuccess "parse rejects invalid characters (I, L)"
      Data.Either.Right _ -> Replay.Common.TestFailure "parse rejects invalid characters (I, L)" "Should have rejected string with I and L"

testParseRejectsOCharacter :: Replay.Common.TestResult
testParseRejectsOCharacter =
  let
    invalidULID = "01ARZ3NDEKTSV4RRFFQ69G5FOO"
    result = Replay.ULID.parse invalidULID
  in
    case result of
      Data.Either.Left _ -> Replay.Common.TestSuccess "parse rejects O character"
      Data.Either.Right _ -> Replay.Common.TestFailure "parse rejects O character" "Should have rejected string with O"

testParseRejectsUCharacter :: Replay.Common.TestResult
testParseRejectsUCharacter =
  let
    invalidULID = "01ARZ3NDEKTSV4RRFFQ69G5FUU"
    result = Replay.ULID.parse invalidULID
  in
    case result of
      Data.Either.Left _ -> Replay.Common.TestSuccess "parse rejects U character"
      Data.Either.Right _ -> Replay.Common.TestFailure "parse rejects U character" "Should have rejected string with U"

testFromStringReturnsJustForValid :: Replay.Common.TestResult
testFromStringReturnsJustForValid =
  let
    validULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
    result = Replay.ULID.fromString validULID
  in
    case result of
      Data.Maybe.Just ulid ->
        if Replay.ULID.toString ulid == validULID then
          Replay.Common.TestSuccess "fromString returns Just for valid ULID"
        else
          Replay.Common.TestFailure "fromString returns Just for valid ULID" "String mismatch"
      Data.Maybe.Nothing ->
        Replay.Common.TestFailure "fromString returns Just for valid ULID" "Returned Nothing"

testFromStringReturnsNothingForInvalid :: Replay.Common.TestResult
testFromStringReturnsNothingForInvalid =
  let
    invalidULID = "invalid"
    result = Replay.ULID.fromString invalidULID
  in
    case result of
      Data.Maybe.Nothing -> Replay.Common.TestSuccess "fromString returns Nothing for invalid ULID"
      Data.Maybe.Just _ -> Replay.Common.TestFailure "fromString returns Nothing for invalid ULID" "Should have returned Nothing"

testTimestampExtraction :: Effect.Effect Replay.Common.TestResult
testTimestampExtraction = do
  let knownTimestamp = Replay.ULID.Timestamp 1704067200000.0
  ulid <- Replay.ULID.generateAt knownTimestamp
  extractedTimestamp <- Replay.ULID.timestamp ulid
  let (Replay.ULID.Timestamp extracted) = extractedTimestamp
  let (Replay.ULID.Timestamp expected) = knownTimestamp
  pure $
    if extracted == expected then
      Replay.Common.TestSuccess "timestamp extraction returns correct value"
    else
      Replay.Common.TestFailure "timestamp extraction returns correct value"
        ("Expected: " <> show expected <> ", Got: " <> show extracted)

testSortingChronological :: Effect.Effect Replay.Common.TestResult
testSortingChronological = do
  let earlierTimestamp = Replay.ULID.Timestamp 1704067200000.0
  let laterTimestamp = Replay.ULID.Timestamp 1704153600000.0
  earlier <- Replay.ULID.generateAt earlierTimestamp
  later <- Replay.ULID.generateAt laterTimestamp
  let sorted = Data.Array.sort [ later, earlier ]
  case sorted of
    [ first, second ] ->
      pure $
        if first == earlier && second == later then
          Replay.Common.TestSuccess "ULIDs sort chronologically (earlier < later)"
        else
          Replay.Common.TestFailure "ULIDs sort chronologically (earlier < later)"
            ("Expected earlier first, got: " <> Replay.ULID.toString first <> ", " <> Replay.ULID.toString second)
    _ ->
      pure $ Replay.Common.TestFailure "ULIDs sort chronologically (earlier < later)" "Unexpected array length"

testOrdInstanceConsistent :: Replay.Common.TestResult
testOrdInstanceConsistent =
  let
    ulid1Result = Replay.ULID.parse "01ARZ3NDEKTSV4RRFFQ69G5FAA"
    ulid2Result = Replay.ULID.parse "01ARZ3NDEKTSV4RRFFQ69G5FAB"
    ulid3Result = Replay.ULID.parse "01ARZ3NDEKTSV4RRFFQ69G5FAC"
  in
    case ulid1Result, ulid2Result, ulid3Result of
      Data.Either.Right ulid1, Data.Either.Right ulid2, Data.Either.Right ulid3 ->
        let
          transitivityOk = ulid1 < ulid2 && ulid2 < ulid3 && ulid1 < ulid3
          reflexivityOk = ulid1 == ulid1
          antisymmetryOk = not (ulid1 < ulid2 && ulid2 < ulid1)
        in
          if transitivityOk && reflexivityOk && antisymmetryOk then
            Replay.Common.TestSuccess "Ord instance is consistent (transitive, reflexive, antisymmetric)"
          else
            Replay.Common.TestFailure "Ord instance is consistent" "Ord laws violated"
      _, _, _ ->
        Replay.Common.TestFailure "Ord instance is consistent" "Could not parse test ULIDs"

testJsonRoundtrip :: Effect.Effect Replay.Common.TestResult
testJsonRoundtrip = do
  ulid <- Replay.ULID.generate
  let encoded = Data.Argonaut.Encode.encodeJson ulid
  let decoded = Data.Argonaut.Decode.decodeJson encoded
  pure $ case decoded of
    Data.Either.Right decodedUlid ->
      if decodedUlid == ulid then
        Replay.Common.TestSuccess "JSON encode/decode roundtrip"
      else
        Replay.Common.TestFailure "JSON encode/decode roundtrip" "Decoded value differs from original"
    Data.Either.Left err ->
      Replay.Common.TestFailure "JSON encode/decode roundtrip" (Data.Argonaut.Decode.printJsonDecodeError err)

testJsonEncodesToString :: Effect.Effect Replay.Common.TestResult
testJsonEncodesToString = do
  ulid <- Replay.ULID.generate
  let encoded = Data.Argonaut.Encode.encodeJson ulid
  let str = Data.Argonaut.Core.stringify encoded
  let ulidStr = Replay.ULID.toString ulid
  pure $
    if str == "\"" <> ulidStr <> "\"" then
      Replay.Common.TestSuccess "JSON encodes ULID as string"
    else
      Replay.Common.TestFailure "JSON encodes ULID as string" ("Expected quoted string, got: " <> str)

testJsonDecodesInvalidULID :: Replay.Common.TestResult
testJsonDecodesInvalidULID =
  let
    invalidJson = Data.Argonaut.Core.fromString "invalid-ulid"

    decoded :: Data.Either.Either Data.Argonaut.Decode.JsonDecodeError Replay.ULID.ULID
    decoded = Data.Argonaut.Decode.decodeJson invalidJson
  in
    case decoded of
      Data.Either.Left _ -> Replay.Common.TestSuccess "JSON decode rejects invalid ULID string"
      Data.Either.Right _ -> Replay.Common.TestFailure "JSON decode rejects invalid ULID string" "Should have rejected invalid ULID"

testTimestampJsonRoundtrip :: Replay.Common.TestResult
testTimestampJsonRoundtrip =
  let
    ts = Replay.ULID.Timestamp 1704067200000.0
    encoded = Data.Argonaut.Encode.encodeJson ts
    decoded = Data.Argonaut.Decode.decodeJson encoded
  in
    case decoded of
      Data.Either.Right decodedTs ->
        if decodedTs == ts then
          Replay.Common.TestSuccess "Timestamp JSON encode/decode roundtrip"
        else
          Replay.Common.TestFailure "Timestamp JSON encode/decode roundtrip" "Decoded value differs"
      Data.Either.Left err ->
        Replay.Common.TestFailure "Timestamp JSON encode/decode roundtrip" (Data.Argonaut.Decode.printJsonDecodeError err)

matchesCrockfordBase32 :: String -> Boolean
matchesCrockfordBase32 str =
  case Data.String.Regex.regex "^[0-9A-HJKMNP-TV-Z]{26}$" Data.String.Regex.Flags.noFlags of
    Data.Either.Left _ -> false
    Data.Either.Right pattern -> Data.String.Regex.test pattern (Data.String.toUpper str)

pureTests :: Array Replay.Common.TestResult
pureTests =
  [ testParseAcceptsValidULID
  , testParseAcceptsLowercaseULID
  , testParseRejectsTooShort
  , testParseRejectsTooLong
  , testParseRejectsInvalidCharacters
  , testParseRejectsOCharacter
  , testParseRejectsUCharacter
  , testFromStringReturnsJustForValid
  , testFromStringReturnsNothingForInvalid
  , testOrdInstanceConsistent
  , testJsonDecodesInvalidULID
  , testTimestampJsonRoundtrip
  ]

effectTests :: Effect.Effect (Array Replay.Common.TestResult)
effectTests = do
  r1 <- testGenerateProducesValidFormat
  r2 <- testGenerateAtProducesValidFormat
  r3 <- testGenerateProducesUniqueValues
  r4 <- testTimestampExtraction
  r5 <- testSortingChronological
  r6 <- testJsonRoundtrip
  r7 <- testJsonEncodesToString
  pure [ r1, r2, r3, r4, r5, r6, r7 ]

runTests :: Effect.Effect Replay.Common.TestResults
runTests = do
  effectResults <- effectTests
  let allResults = pureTests <> effectResults
  pure $ Replay.Common.computeResults allResults
