module Signal
  ( SignalType(..)
  , onSignal
  , onUncaughtException
  , onUnhandledRejection
  , formatError
  ) where

import Prelude

import Effect as Effect
import Effect.Uncurried as Effect.Uncurried
import Foreign as Foreign

data SignalType
  = SIGINT
  | SIGTERM

signalTypeToString :: SignalType -> String
signalTypeToString SIGINT = "SIGINT"
signalTypeToString SIGTERM = "SIGTERM"

foreign import onSignalImpl
  :: Effect.Uncurried.EffectFn2
       String
       (Effect.Effect Unit)
       Unit

onSignal :: SignalType -> Effect.Effect Unit -> Effect.Effect Unit
onSignal signalType handler =
  Effect.Uncurried.runEffectFn2 onSignalImpl (signalTypeToString signalType) handler

foreign import onUncaughtExceptionImpl
  :: Effect.Uncurried.EffectFn1
       (Foreign.Foreign -> Effect.Effect Unit)
       Unit

onUncaughtException :: (Foreign.Foreign -> Effect.Effect Unit) -> Effect.Effect Unit
onUncaughtException handler =
  Effect.Uncurried.runEffectFn1 onUncaughtExceptionImpl handler

foreign import onUnhandledRejectionImpl
  :: Effect.Uncurried.EffectFn1
       (Foreign.Foreign -> Effect.Effect Unit)
       Unit

onUnhandledRejection :: (Foreign.Foreign -> Effect.Effect Unit) -> Effect.Effect Unit
onUnhandledRejection handler =
  Effect.Uncurried.runEffectFn1 onUnhandledRejectionImpl handler

foreign import formatErrorImpl
  :: Effect.Uncurried.EffectFn1
       Foreign.Foreign
       String

formatError :: Foreign.Foreign -> Effect.Effect String
formatError err =
  Effect.Uncurried.runEffectFn1 formatErrorImpl err
