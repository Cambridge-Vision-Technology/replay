module Replay.Common
  ( TestResult(..)
  , TestResults
  , FailureInfo
  , isSuccess
  , computeResults
  ) where

import Prelude

import Data.Array as Data.Array

data TestResult
  = TestSuccess String
  | TestFailure String String

derive instance Eq TestResult

instance Show TestResult where
  show (TestSuccess name) = "PASS: " <> name
  show (TestFailure name err) = "FAIL: " <> name <> " - " <> err

type FailureInfo =
  { name :: String
  , reason :: String
  }

type TestResults =
  { passed :: Int
  , failed :: Int
  , total :: Int
  , results :: Array TestResult
  , failures :: Array FailureInfo
  }

isSuccess :: TestResult -> Boolean
isSuccess (TestSuccess _) = true
isSuccess (TestFailure _ _) = false

toFailureInfo :: TestResult -> Array FailureInfo
toFailureInfo (TestSuccess _) = []
toFailureInfo (TestFailure name reason) = [ { name, reason } ]

computeResults :: Array TestResult -> TestResults
computeResults results =
  let
    passed = Data.Array.length (Data.Array.filter isSuccess results)
    failed = Data.Array.length results - passed
    total = Data.Array.length results
    failures = Data.Array.concatMap toFailureInfo results
  in
    { passed, failed, total, results, failures }
