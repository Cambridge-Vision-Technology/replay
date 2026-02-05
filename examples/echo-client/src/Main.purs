module EchoClient.Main where

import Prelude

import Control.Monad.Error.Class as Control.Monad.Error.Class
import Control.Promise as Control.Promise
import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Argonaut.Decode as Data.Argonaut.Decode
import Data.Argonaut.Encode as Data.Argonaut.Encode
import Data.Argonaut.Encode ((:=), (~>))
import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Maybe as Data.Maybe
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Console as Effect.Console
import Effect.Uncurried as Effect.Uncurried
import Json.Nullable as Json.Nullable
import Node.Process as Node.Process
import Replay.Client as Replay.Client
import Replay.Protocol.Types as Replay.Protocol.Types
import Replay.Time as Replay.Time
import Replay.ULID as Replay.ULID

foreign import fetchImpl
  :: Effect.Uncurried.EffectFn3
       String
       String
       String
       (Control.Promise.Promise FetchResponse)

type FetchResponse =
  { statusCode :: Int
  , body :: String
  }

fetch :: String -> String -> String -> Effect.Aff.Aff FetchResponse
fetch url method body = do
  promise <- Effect.Class.liftEffect $ Effect.Uncurried.runEffectFn3 fetchImpl url method body
  Control.Promise.toAff promise

type HttpRequestPayload =
  { method :: String
  , url :: String
  , body :: Data.Maybe.Maybe String
  , headers :: Data.Maybe.Maybe (Array { name :: String, value :: String })
  }

type HttpResponsePayload =
  { statusCode :: Int
  , body :: String
  }

encodeHttpRequest :: HttpRequestPayload -> Data.Argonaut.Core.Json
encodeHttpRequest req =
  "method" := req.method
    ~> "url" := req.url
    ~> "body" := req.body
    ~> "headers" := req.headers
    ~> Data.Argonaut.Core.jsonEmptyObject

decodeHttpResponse :: Data.Argonaut.Core.Json -> Data.Either.Either String HttpResponsePayload
decodeHttpResponse json = do
  case Data.Argonaut.Decode.decodeJson json of
    Data.Either.Left err ->
      Data.Either.Left $ Data.Argonaut.Decode.printJsonDecodeError err
    Data.Either.Right (obj :: { statusCode :: Int, body :: String }) ->
      Data.Either.Right obj

main :: Effect.Effect Unit
main = do
  argv <- Node.Process.argv
  let args = Data.Array.drop 2 argv
  case Data.Array.head args of
    Data.Maybe.Nothing -> do
      Effect.Console.error "Usage: echo-client <message>"
      Node.Process.exit' 1
    Data.Maybe.Just message -> do
      maybeUrl <- Node.Process.lookupEnv "PLATFORM_URL"
      Effect.Aff.runAff_ handleResult do
        case maybeUrl of
          Data.Maybe.Nothing ->
            runDirectHttp message
          Data.Maybe.Just socketPath ->
            runViaHarness socketPath message
  where
  handleResult :: Data.Either.Either Effect.Aff.Error String -> Effect.Effect Unit
  handleResult (Data.Either.Left err) = do
    Effect.Console.error $ "Error: " <> Effect.Aff.message err
    Node.Process.exit' 1
  handleResult (Data.Either.Right output) = do
    Effect.Console.log output
    pure unit

runDirectHttp :: String -> Effect.Aff.Aff String
runDirectHttp message = do
  let
    url = "https://httpbin.org/anything"
    body = Data.Argonaut.Core.stringify $ "message" := message ~> Data.Argonaut.Core.jsonEmptyObject
  response <- fetch url "POST" body
  if response.statusCode >= 200 && response.statusCode < 300 then
    pure response.body
  else
    Control.Monad.Error.Class.throwError $ Effect.Aff.error $ "HTTP error: " <> show response.statusCode

runViaHarness :: String -> String -> Effect.Aff.Aff String
runViaHarness socketPath message = do
  connectionResult <- Replay.Client.connectToSocket socketPath
  case connectionResult of
    Data.Either.Left err -> do
      Control.Monad.Error.Class.throwError $ Effect.Aff.error $ "Failed to connect to harness: " <> show err
    Data.Either.Right conn -> do
      result <- sendHttpRequest conn message
      Replay.Client.disconnect conn
      pure result

sendHttpRequest :: Replay.Client.WebSocketConnection -> String -> Effect.Aff.Aff String
sendHttpRequest conn message = Effect.Aff.makeAff \callback -> do
  ulid1 <- Replay.ULID.generate
  ulid2 <- Replay.ULID.generate
  timestamp <- Replay.Time.getCurrentTimestamp
  let streamId = Replay.ULID.toString ulid1
  let traceId = Replay.ULID.toString ulid2

  let
    httpRequest :: HttpRequestPayload
    httpRequest =
      { method: "POST"
      , url: "https://httpbin.org/anything"
      , body: Data.Maybe.Just $ Data.Argonaut.Core.stringify $ "message" := message ~> Data.Argonaut.Core.jsonEmptyObject
      , headers: Data.Maybe.Just [ { name: "Content-Type", value: "application/json" } ]
      }

    requestPayload :: Replay.Protocol.Types.RequestPayload
    requestPayload = Replay.Protocol.Types.mkRequestPayload "http" (encodeHttpRequest httpRequest)

    commandEnvelope :: Replay.Protocol.Types.Envelope Replay.Protocol.Types.Command
    commandEnvelope = Replay.Protocol.Types.Envelope
      { streamId: Replay.Protocol.Types.StreamId streamId
      , traceId: Replay.Protocol.Types.TraceId traceId
      , causationStreamId: Json.Nullable.jsonNull
      , parentStreamId: Json.Nullable.jsonNull
      , siblingIndex: Replay.Protocol.Types.SiblingIndex 0
      , eventSeq: Replay.Protocol.Types.EventSeq 0
      , timestamp
      , channel: Replay.Protocol.Types.ProgramChannel
      , payloadHash: Data.Maybe.Nothing
      , payload: Replay.Protocol.Types.CommandOpen requestPayload
      }

    handleMessage :: String -> Effect.Effect Unit
    handleMessage msg = do
      case Replay.Client.parseIncomingMessage msg of
        Replay.Client.IncomingPlatformEvent envelope -> do
          let (Replay.Protocol.Types.Envelope env) = envelope
          case env.payload of
            Replay.Protocol.Types.EventClose responsePayload -> do
              if responsePayload.service == "http" then do
                case decodeHttpResponse responsePayload.payload of
                  Data.Either.Left err ->
                    callback (Data.Either.Left $ Effect.Aff.error $ "Failed to decode response: " <> err)
                  Data.Either.Right httpResp -> do
                    if httpResp.statusCode >= 200 && httpResp.statusCode < 300 then
                      callback (Data.Either.Right httpResp.body)
                    else
                      callback (Data.Either.Left $ Effect.Aff.error $ "HTTP error: " <> show httpResp.statusCode)
              else
                pure unit
            _ ->
              pure unit
        Replay.Client.ParseError err ->
          callback (Data.Either.Left $ Effect.Aff.error $ "Parse error: " <> err)
        _ ->
          pure unit

  Replay.Client.onMessage conn handleMessage
  Replay.Client.sendCommand conn commandEnvelope

  pure Effect.Aff.nonCanceler
