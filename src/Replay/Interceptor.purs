module Replay.Interceptor
  ( InterceptRegistry
  , InterceptEntry
  , InterceptStats
  , InterceptResult
  , newRegistry
  , register
  , remove
  , clear
  , listAll
  , getStats
  , getActiveCount
  , matchRequest
  ) where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Array as Data.Array
import Data.Foldable as Data.Foldable
import Data.Map as Data.Map
import Data.Maybe as Data.Maybe
import Data.String as Data.String
import Data.Tuple as Data.Tuple
import Effect as Effect
import Effect.Ref as Effect.Ref
import Foreign.Object as Foreign.Object
import Replay.Protocol.Types as Replay.Protocol.Types
import Replay.ULID as Replay.ULID

-- | Internal state for an intercept registration
type InterceptState =
  { spec :: Replay.Protocol.Types.InterceptSpec
  , matchCount :: Int
  }

-- | Registry holding all active intercepts
-- | Opaque type to prevent direct manipulation
newtype InterceptRegistry = InterceptRegistry
  { interceptsRef :: Effect.Ref.Ref (Data.Map.Map Replay.Protocol.Types.InterceptId InterceptState)
  }

-- | Entry returned when listing intercepts
type InterceptEntry =
  { interceptId :: Replay.Protocol.Types.InterceptId
  , spec :: Replay.Protocol.Types.InterceptSpec
  , matchCount :: Int
  , remainingMatches :: Data.Maybe.Maybe Int
  }

-- | Stats for a specific intercept
type InterceptStats =
  { matchCount :: Int
  , remainingMatches :: Data.Maybe.Maybe Int
  , isActive :: Boolean
  }

-- | Create an empty intercept registry
newRegistry :: Effect.Effect InterceptRegistry
newRegistry = do
  interceptsRef <- Effect.Ref.new Data.Map.empty
  pure (InterceptRegistry { interceptsRef })

-- | Register a new intercept and return its unique ID
register :: Replay.Protocol.Types.InterceptSpec -> InterceptRegistry -> Effect.Effect Replay.Protocol.Types.InterceptId
register spec (InterceptRegistry registry) = do
  ulid <- Replay.ULID.generate
  let interceptId = Replay.Protocol.Types.InterceptId (Replay.ULID.toString ulid)
  let state = { spec, matchCount: 0 }
  Effect.Ref.modify_ (Data.Map.insert interceptId state) registry.interceptsRef
  pure interceptId

-- | Remove an intercept by ID
-- | Returns true if the intercept was found and removed, false otherwise
remove :: Replay.Protocol.Types.InterceptId -> InterceptRegistry -> Effect.Effect Boolean
remove interceptId (InterceptRegistry registry) = do
  intercepts <- Effect.Ref.read registry.interceptsRef
  if Data.Map.member interceptId intercepts then do
    Effect.Ref.modify_ (Data.Map.delete interceptId) registry.interceptsRef
    pure true
  else
    pure false

-- | Clear intercepts, optionally filtered by service type (as String)
-- | Returns the number of intercepts cleared
clear :: Data.Maybe.Maybe String -> InterceptRegistry -> Effect.Effect Int
clear maybeServiceType (InterceptRegistry registry) = do
  intercepts <- Effect.Ref.read registry.interceptsRef
  let
    toRemove = case maybeServiceType of
      Data.Maybe.Nothing ->
        intercepts
      Data.Maybe.Just serviceType ->
        Data.Map.filter (\state -> state.spec.match.service == serviceType) intercepts
    keysToRemove = Data.Map.keys toRemove
    removeCount = Data.Array.length (Data.Array.fromFoldable keysToRemove)
  Effect.Ref.modify_ (\m -> Data.Foldable.foldl (flip Data.Map.delete) m keysToRemove) registry.interceptsRef
  pure removeCount

-- | List all active intercepts with their current stats
listAll :: InterceptRegistry -> Effect.Effect (Array InterceptEntry)
listAll (InterceptRegistry registry) = do
  intercepts <- Effect.Ref.read registry.interceptsRef
  let entries = Data.Map.toUnfoldable intercepts :: Array (Data.Tuple.Tuple Replay.Protocol.Types.InterceptId InterceptState)
  pure $ map toEntry entries
  where
  toEntry :: Data.Tuple.Tuple Replay.Protocol.Types.InterceptId InterceptState -> InterceptEntry
  toEntry (Data.Tuple.Tuple interceptId state) =
    { interceptId
    , spec: state.spec
    , matchCount: state.matchCount
    , remainingMatches: computeRemainingMatches state.spec.times state.matchCount
    }

-- | Get stats for a specific intercept
-- | Returns Nothing if the intercept ID is not found
getStats :: Replay.Protocol.Types.InterceptId -> InterceptRegistry -> Effect.Effect (Data.Maybe.Maybe InterceptStats)
getStats interceptId (InterceptRegistry registry) = do
  intercepts <- Effect.Ref.read registry.interceptsRef
  pure $ Data.Map.lookup interceptId intercepts <#> \state ->
    { matchCount: state.matchCount
    , remainingMatches: computeRemainingMatches state.spec.times state.matchCount
    , isActive: isStillActive state.spec.times state.matchCount
    }

-- | Get the count of active intercepts
getActiveCount :: InterceptRegistry -> Effect.Effect Int
getActiveCount (InterceptRegistry registry) = do
  intercepts <- Effect.Ref.read registry.interceptsRef
  let activeIntercepts = Data.Map.filter isInterceptActive intercepts
  pure $ Data.Map.size activeIntercepts
  where
  isInterceptActive :: InterceptState -> Boolean
  isInterceptActive state = isStillActive state.spec.times state.matchCount

-- | Compute remaining matches from times limit and current match count
computeRemainingMatches :: Data.Maybe.Maybe Int -> Int -> Data.Maybe.Maybe Int
computeRemainingMatches Data.Maybe.Nothing _ = Data.Maybe.Nothing
computeRemainingMatches (Data.Maybe.Just times) matchCount =
  Data.Maybe.Just (max 0 (times - matchCount))

-- | Check if an intercept is still active (has matches remaining)
isStillActive :: Data.Maybe.Maybe Int -> Int -> Boolean
isStillActive Data.Maybe.Nothing _ = true
isStillActive (Data.Maybe.Just times) matchCount = matchCount < times

-- | Result returned when an intercept matches a request
type InterceptResult =
  { response :: Replay.Protocol.Types.ResponsePayload
  , delay :: Data.Maybe.Maybe Replay.Protocol.Types.Milliseconds
  , interceptId :: Replay.Protocol.Types.InterceptId
  }

-- | Match a request against all active intercepts
-- | Returns the response from the highest-priority matching intercept
-- | and increments its match count
matchRequest
  :: Replay.Protocol.Types.RequestPayload
  -> InterceptRegistry
  -> Effect.Effect (Data.Maybe.Maybe InterceptResult)
matchRequest payload (InterceptRegistry registry) = do
  intercepts <- Effect.Ref.read registry.interceptsRef
  let entries = Data.Map.toUnfoldable intercepts :: Array (Data.Tuple.Tuple Replay.Protocol.Types.InterceptId InterceptState)
  let sortedByPriority = Data.Array.sortBy (comparing (negate <<< _.spec.priority <<< Data.Tuple.snd)) entries
  findFirstMatch sortedByPriority
  where
  findFirstMatch
    :: Array (Data.Tuple.Tuple Replay.Protocol.Types.InterceptId InterceptState)
    -> Effect.Effect (Data.Maybe.Maybe InterceptResult)
  findFirstMatch arr = case Data.Array.uncons arr of
    Data.Maybe.Nothing ->
      pure Data.Maybe.Nothing
    Data.Maybe.Just { head: Data.Tuple.Tuple interceptId state, tail } ->
      let
        matches = matchesRequest payload state.spec.match
      in
        if isStillActive state.spec.times state.matchCount && matches then do
          incrementMatchCount interceptId
          pure $ Data.Maybe.Just
            { response: state.spec.response
            , delay: state.spec.delay
            , interceptId
            }
        else
          findFirstMatch tail

  incrementMatchCount :: Replay.Protocol.Types.InterceptId -> Effect.Effect Unit
  incrementMatchCount interceptId =
    Effect.Ref.modify_
      (Data.Map.update (\s -> Data.Maybe.Just (s { matchCount = s.matchCount + 1 })) interceptId)
      registry.interceptsRef

-- | Check if a request payload matches an intercept's match criteria
matchesRequest
  :: Replay.Protocol.Types.RequestPayload
  -> Replay.Protocol.Types.InterceptMatch
  -> Boolean
matchesRequest payload matchSpec =
  matchesServiceType payload matchSpec.service
    && matchesFunctionName payload matchSpec.functionName
    && matchesUrl payload matchSpec.urlMatch
    && matchesMethod payload matchSpec.method

-- | Check if request matches the service type (as String)
matchesServiceType :: Replay.Protocol.Types.RequestPayload -> String -> Boolean
matchesServiceType payload serviceType =
  payload.service == serviceType

-- | Check if request matches function name filter (extracted from payload JSON)
matchesFunctionName :: Replay.Protocol.Types.RequestPayload -> Data.Maybe.Maybe String -> Boolean
matchesFunctionName _ Data.Maybe.Nothing = true
matchesFunctionName payload (Data.Maybe.Just fnName) =
  case getJsonField "functionName" payload.payload of
    Data.Maybe.Just actualFnName -> actualFnName == fnName
    Data.Maybe.Nothing -> false

-- | Check if request matches URL filter (extracted from payload JSON)
matchesUrl
  :: Replay.Protocol.Types.RequestPayload
  -> Data.Maybe.Maybe Replay.Protocol.Types.UrlMatch
  -> Boolean
matchesUrl _ Data.Maybe.Nothing = true
matchesUrl payload (Data.Maybe.Just urlMatch) =
  case getJsonField "url" payload.payload of
    Data.Maybe.Just actualUrl -> matchUrlAgainst actualUrl urlMatch
    Data.Maybe.Nothing -> false

-- | Check if URL matches the given UrlMatch specification
matchUrlAgainst :: String -> Replay.Protocol.Types.UrlMatch -> Boolean
matchUrlAgainst url (Replay.Protocol.Types.UrlExact exact) = url == exact
matchUrlAgainst url (Replay.Protocol.Types.UrlContains substr) =
  Data.String.contains (Data.String.Pattern substr) url

-- | Check if request matches HTTP method filter (extracted from payload JSON)
matchesMethod :: Replay.Protocol.Types.RequestPayload -> Data.Maybe.Maybe String -> Boolean
matchesMethod _ Data.Maybe.Nothing = true
matchesMethod payload (Data.Maybe.Just method) =
  case getJsonField "method" payload.payload of
    Data.Maybe.Just actualMethod -> actualMethod == method
    Data.Maybe.Nothing -> false

-- | Extract a string field from JSON
getJsonField :: String -> Data.Argonaut.Core.Json -> Data.Maybe.Maybe String
getJsonField fieldName json =
  case Data.Argonaut.Core.toObject json of
    Data.Maybe.Nothing -> Data.Maybe.Nothing
    Data.Maybe.Just obj ->
      case Foreign.Object.lookup fieldName obj of
        Data.Maybe.Nothing -> Data.Maybe.Nothing
        Data.Maybe.Just value ->
          Data.Argonaut.Core.toString value
