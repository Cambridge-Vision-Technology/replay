module Main where

import Prelude

import Control.Alt ((<|>))
import Data.Array as Data.Array
import Data.Either as Data.Either
import Data.Foldable as Data.Foldable
import Data.Maybe as Data.Maybe
import Data.Tuple as Data.Tuple
import Effect as Effect
import Effect.Aff as Effect.Aff
import Effect.Class as Effect.Class
import Effect.Console as Effect.Console
import Effect.Ref as Effect.Ref
import Node.Process as Node.Process
import Options.Applicative as Options.Applicative
import Options.Applicative ((<**>))
import Options.Applicative.Builder as Options.Applicative.Builder
import Options.Applicative.Extra as Options.Applicative.Extra
import Options.Applicative.Types as Options.Applicative.Types
import Replay.Player as Replay.Player
import Replay.Recorder as Replay.Recorder
import Replay.Recording as Replay.Recording
import Replay.Server as Replay.Server
import Replay.Session as Replay.Session
import Replay.Types as Replay.Types
import Signal as Signal

defaultHarnessPort :: Int
defaultHarnessPort = 9876

type HarnessOptions =
  { mode :: Replay.Types.HarnessMode
  , port :: Int
  , socket :: Data.Maybe.Maybe String
  , recordingPath :: Data.Maybe.Maybe String
  , recordingDir :: Data.Maybe.Maybe String
  }

modeReader :: Options.Applicative.Types.ReadM Replay.Types.HarnessMode
modeReader = Options.Applicative.Builder.eitherReader parseModeString
  where
  parseModeString :: String -> Data.Either.Either String Replay.Types.HarnessMode
  parseModeString "passthrough" = Data.Either.Right Replay.Types.ModePassthrough
  parseModeString "record" = Data.Either.Right Replay.Types.ModeRecord
  parseModeString "playback" = Data.Either.Right Replay.Types.ModePlayback
  parseModeString other = Data.Either.Left $ "Invalid mode: " <> other <> ". Must be one of: passthrough, record, playback"

optionsParser :: Options.Applicative.Types.Parser HarnessOptions
optionsParser = ado
  mode <-
    Options.Applicative.Builder.option modeReader
      ( Options.Applicative.Builder.long "mode"
          <> Options.Applicative.Builder.short 'm'
          <> Options.Applicative.Builder.metavar "MODE"
          <> Options.Applicative.Builder.value Replay.Types.ModePassthrough
          <> Options.Applicative.Builder.showDefaultWith showMode
          <> Options.Applicative.Builder.help "Harness mode: passthrough, record, or playback"
      )
  port <-
    Options.Applicative.Builder.option Options.Applicative.int
      ( Options.Applicative.Builder.long "port"
          <> Options.Applicative.Builder.short 'p'
          <> Options.Applicative.Builder.metavar "PORT"
          <> Options.Applicative.Builder.value defaultHarnessPort
          <> Options.Applicative.Builder.showDefault
          <> Options.Applicative.Builder.help "WebSocket server port (ignored if --socket is provided)"
      )
  socket <-
    optional
      ( Options.Applicative.Builder.strOption
          ( Options.Applicative.Builder.long "socket"
              <> Options.Applicative.Builder.short 's'
              <> Options.Applicative.Builder.metavar "PATH"
              <> Options.Applicative.Builder.help "Unix socket path (alternative to --port)"
          )
      )
  recordingPath <-
    optional
      ( Options.Applicative.Builder.strOption
          ( Options.Applicative.Builder.long "recording-path"
              <> Options.Applicative.Builder.short 'r'
              <> Options.Applicative.Builder.metavar "PATH"
              <> Options.Applicative.Builder.help "Path to recording file (for single-session backward compatibility)"
          )
      )
  recordingDir <-
    optional
      ( Options.Applicative.Builder.strOption
          ( Options.Applicative.Builder.long "recording-dir"
              <> Options.Applicative.Builder.short 'd'
              <> Options.Applicative.Builder.metavar "PATH"
              <> Options.Applicative.Builder.help "Base directory for session recordings (session mode)"
          )
      )
  in
    { mode, port, socket, recordingPath, recordingDir }
  where
  showMode :: Replay.Types.HarnessMode -> String
  showMode Replay.Types.ModePassthrough = "passthrough"
  showMode Replay.Types.ModeRecord = "record"
  showMode Replay.Types.ModePlayback = "playback"

  optional :: forall a. Options.Applicative.Types.Parser a -> Options.Applicative.Types.Parser (Data.Maybe.Maybe a)
  optional p = (Data.Maybe.Just <$> p) <|> pure Data.Maybe.Nothing

parserInfo :: Options.Applicative.Types.ParserInfo HarnessOptions
parserInfo =
  Options.Applicative.Builder.info (optionsParser <**> Options.Applicative.helper)
    ( Options.Applicative.Builder.fullDesc
        <> Options.Applicative.Builder.progDesc "Test harness server for recording and playback"
        <> Options.Applicative.Builder.header "replay - WebSocket-based test harness"
    )

parseOptions :: Array String -> Options.Applicative.Types.ParserResult HarnessOptions
parseOptions args =
  Options.Applicative.Extra.execParserPure Options.Applicative.Builder.defaultPrefs parserInfo args

main :: Effect.Effect Unit
main = do
  installUncaughtExceptionHandler
  installUnhandledRejectionHandler
  argv <- Node.Process.argv
  let cliArgs = Data.Array.drop 2 argv
  case parseOptions cliArgs of
    Options.Applicative.Types.Success opts ->
      runHarness opts

    Options.Applicative.Types.Failure failure -> do
      let Data.Tuple.Tuple helpText _ = Options.Applicative.Extra.renderFailure failure "replay"
      Effect.Console.log helpText
      Node.Process.exit' 1

    Options.Applicative.Types.CompletionInvoked (Options.Applicative.Types.CompletionResult { execCompletion }) -> do
      completionOutput <- execCompletion "replay"
      Effect.Console.log completionOutput
      Node.Process.exit' 0

installUncaughtExceptionHandler :: Effect.Effect Unit
installUncaughtExceptionHandler =
  Signal.onUncaughtException \err -> do
    errMsg <- Signal.formatError err
    Effect.Console.error $ "FATAL: Uncaught exception: " <> errMsg
    Node.Process.exit' 1

installUnhandledRejectionHandler :: Effect.Effect Unit
installUnhandledRejectionHandler =
  Signal.onUnhandledRejection \reason -> do
    reasonMsg <- Signal.formatError reason
    Effect.Console.error $ "FATAL: Unhandled promise rejection: " <> reasonMsg
    Node.Process.exit' 1

runHarness :: HarnessOptions -> Effect.Effect Unit
runHarness opts = do
  case validateOptions opts of
    Data.Either.Left err -> do
      Effect.Console.error $ "Error: " <> err
      Node.Process.exit' 1
    Data.Either.Right _ -> do
      Effect.Aff.runAff_ handleAffError $ startHarnessWithShutdown opts
  where
  handleAffError :: Data.Either.Either Effect.Aff.Error Unit -> Effect.Effect Unit
  handleAffError (Data.Either.Left err) = do
    Effect.Console.error $ "FATAL: Harness Aff error: " <> Effect.Aff.message err
    Node.Process.exit' 1
  handleAffError (Data.Either.Right _) =
    pure unit

validateOptions :: HarnessOptions -> Data.Either.Either String Unit
validateOptions opts = do
  case opts.mode of
    Replay.Types.ModeRecord ->
      case opts.recordingPath, opts.recordingDir of
        Data.Maybe.Nothing, Data.Maybe.Nothing -> Data.Either.Left "Record mode requires --recording-path or --recording-dir"
        _, _ -> Data.Either.Right unit
    Replay.Types.ModePlayback ->
      case opts.recordingPath, opts.recordingDir of
        Data.Maybe.Nothing, Data.Maybe.Nothing -> Data.Either.Left "Playback mode requires --recording-path or --recording-dir"
        _, _ -> Data.Either.Right unit
    Replay.Types.ModePassthrough ->
      Data.Either.Right unit

startHarnessWithShutdown :: HarnessOptions -> Effect.Aff.Aff Unit
startHarnessWithShutdown opts = do
  let
    listenTarget = case opts.socket of
      Data.Maybe.Just socketPath -> Replay.Types.ListenOnSocket socketPath
      Data.Maybe.Nothing -> Replay.Types.ListenOnPort opts.port

  Effect.Class.liftEffect $ Effect.Console.log $ "replay starting..."
  Effect.Class.liftEffect $ Effect.Console.log $ "  Mode: " <> showModeForDisplay opts.mode
  Effect.Class.liftEffect $ Effect.Console.log $ "  Listen: " <> show listenTarget

  case opts.recordingPath of
    Data.Maybe.Just path ->
      Effect.Class.liftEffect $ Effect.Console.log $ "  Recording path: " <> path
    Data.Maybe.Nothing ->
      pure unit

  case opts.recordingDir of
    Data.Maybe.Just dir ->
      Effect.Class.liftEffect $ Effect.Console.log $ "  Recording dir: " <> dir <> " (session mode)"
    Data.Maybe.Nothing ->
      pure unit

  maybePlayer <- case opts.mode of
    Replay.Types.ModePlayback ->
      case opts.recordingPath of
        Data.Maybe.Just path -> do
          recordingResult <- Replay.Recording.loadRecording path
          case recordingResult of
            Data.Either.Left err -> do
              Effect.Class.liftEffect $ Effect.Console.error $ "Failed to load recording: " <> err
              _ <- Effect.Class.liftEffect $ Node.Process.exit' 1
              pure Data.Maybe.Nothing
            Data.Either.Right recording -> do
              player <- Effect.Class.liftEffect $ Replay.Player.createPlayerState recording
              pure $ Data.Maybe.Just player
        Data.Maybe.Nothing ->
          pure Data.Maybe.Nothing
    _ ->
      pure Data.Maybe.Nothing

  let
    config =
      { listenTarget
      , mode: opts.mode
      , recordingPath: opts.recordingPath
      , baseRecordingDir: opts.recordingDir
      }

  serverResult <- Replay.Server.startHarnessServer config maybePlayer
  case serverResult of
    Data.Either.Left err -> do
      Effect.Class.liftEffect $ Effect.Console.error $ "Failed to start server: " <> show err
      _ <- Effect.Class.liftEffect $ Node.Process.exit' 1
      pure unit

    Data.Either.Right harnessServer -> do
      let
        listenMsg = case listenTarget of
          Replay.Types.ListenOnPort p -> "Harness server listening on port " <> show p
          Replay.Types.ListenOnSocket s -> "Harness server listening on socket " <> s
      Effect.Class.liftEffect $ Effect.Console.log listenMsg

      shutdownRef <- Effect.Class.liftEffect $ Effect.Ref.new false

      let
        shutdownHandler :: Effect.Effect Unit
        shutdownHandler = do
          alreadyShutdown <- Effect.Ref.read shutdownRef
          when (not alreadyShutdown) do
            Effect.Ref.write true shutdownRef
            Effect.Console.log "\nShutting down harness..."
            Effect.Aff.launchAff_ do
              sessionIds <- Effect.Class.liftEffect $ Replay.Session.listSessions harnessServer.sessionRegistry
              Data.Foldable.for_ sessionIds \sessionId -> do
                closeResult <- Replay.Session.closeSession sessionId harnessServer.sessionRegistry
                case closeResult of
                  Data.Either.Left err ->
                    Effect.Class.liftEffect $ Effect.Console.error $ "Failed to close session " <> show sessionId <> ": " <> show err
                  Data.Either.Right _ ->
                    Effect.Class.liftEffect $ Effect.Console.log $ "Session closed: " <> show sessionId

              case harnessServer.mode of
                Replay.Types.ModeRecord ->
                  case harnessServer.recorder of
                    Data.Maybe.Just recorder ->
                      case opts.recordingPath of
                        Data.Maybe.Just path -> do
                          Effect.Class.liftEffect $ Effect.Console.log "Saving recording..."
                          saveResult <- Replay.Recorder.saveRecording recorder path
                          case saveResult of
                            Data.Either.Left err ->
                              Effect.Class.liftEffect $ Effect.Console.error $ "Failed to save recording: " <> err
                            Data.Either.Right _ ->
                              Effect.Class.liftEffect $ Effect.Console.log $ "Recording saved to: " <> path
                        Data.Maybe.Nothing ->
                          pure unit
                    Data.Maybe.Nothing ->
                      pure unit
                _ ->
                  pure unit

              Replay.Server.stopServer harnessServer.server
              Effect.Class.liftEffect $ Effect.Console.log "Harness shutdown complete."
              _ <- Effect.Class.liftEffect $ Node.Process.exit' 0
              pure unit

      Effect.Class.liftEffect $ Signal.onSignal Signal.SIGINT shutdownHandler
      Effect.Class.liftEffect $ Signal.onSignal Signal.SIGTERM shutdownHandler

      Effect.Aff.never

showModeForDisplay :: Replay.Types.HarnessMode -> String
showModeForDisplay Replay.Types.ModePassthrough = "passthrough"
showModeForDisplay Replay.Types.ModeRecord = "record"
showModeForDisplay Replay.Types.ModePlayback = "playback"
