module FFI.Buffer where

import Effect as Effect
import Effect.Uncurried as Effect.Uncurried
import Node.Buffer as Node.Buffer

foreign import toStringImpl :: Effect.Uncurried.EffectFn2 String Node.Buffer.Buffer String
foreign import fromStringImpl :: Effect.Uncurried.EffectFn2 String String Node.Buffer.Buffer

-- | Convert a buffer to a string with the specified encoding
-- | encoding should be "base64", "utf8", "hex", etc.
toString :: String -> Node.Buffer.Buffer -> Effect.Effect String
toString = Effect.Uncurried.runEffectFn2 toStringImpl

-- | Create a buffer from a string with the specified encoding
-- | encoding should be "base64", "utf8", "hex", etc.
fromString :: String -> String -> Effect.Effect Node.Buffer.Buffer
fromString str encoding = Effect.Uncurried.runEffectFn2 fromStringImpl str encoding
