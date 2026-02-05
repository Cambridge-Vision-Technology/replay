module FFI.Crypto where

import Prelude

import Data.Argonaut.Core as Data.Argonaut.Core
import Data.Either as Data.Either
import Effect as Effect
import Effect.Exception as Effect.Exception
import Effect.Uncurried as Effect.Uncurried
import Node.Buffer as Node.Buffer

foreign import md5HashImpl :: Effect.Uncurried.EffectFn1 String String

foreign import randomBytesImpl :: Effect.Uncurried.EffectFn1 Int String

foreign import sha256HashImpl :: Effect.Uncurried.EffectFn1 String String

foreign import canonicalJsonStringifyImpl :: Effect.Uncurried.EffectFn1 Data.Argonaut.Core.Json String

foreign import sha256HashBuffersImpl :: Effect.Uncurried.EffectFn1 (Array Node.Buffer.Buffer) String

foreign import randomBytesBufferImpl :: Effect.Uncurried.EffectFn1 Int Node.Buffer.Buffer

foreign import bufferFromHexImpl :: Effect.Uncurried.EffectFn1 String Node.Buffer.Buffer

foreign import bufferSliceImpl :: Effect.Uncurried.EffectFn3 Int Int Node.Buffer.Buffer Node.Buffer.Buffer

foreign import bufferConcatImpl :: Effect.Uncurried.EffectFn1 (Array Node.Buffer.Buffer) Node.Buffer.Buffer

foreign import bufferSizeImpl :: Effect.Uncurried.EffectFn1 Node.Buffer.Buffer Int

foreign import encryptAes256GcmRawImpl :: Effect.Uncurried.EffectFn3 Node.Buffer.Buffer Node.Buffer.Buffer Node.Buffer.Buffer { ciphertext :: Node.Buffer.Buffer, authTag :: Node.Buffer.Buffer }

foreign import decryptAes256GcmRawImpl :: Effect.Uncurried.EffectFn4 Node.Buffer.Buffer Node.Buffer.Buffer Node.Buffer.Buffer Node.Buffer.Buffer Node.Buffer.Buffer

ivLength :: Int
ivLength = 12

authTagLength :: Int
authTagLength = 16

md5Hash :: String -> Effect.Effect String
md5Hash = Effect.Uncurried.runEffectFn1 md5HashImpl

randomBytes :: Int -> Effect.Effect String
randomBytes = Effect.Uncurried.runEffectFn1 randomBytesImpl

randomBytesBuffer :: Int -> Effect.Effect Node.Buffer.Buffer
randomBytesBuffer = Effect.Uncurried.runEffectFn1 randomBytesBufferImpl

bufferFromHex :: String -> Effect.Effect Node.Buffer.Buffer
bufferFromHex = Effect.Uncurried.runEffectFn1 bufferFromHexImpl

bufferSlice :: Int -> Int -> Node.Buffer.Buffer -> Effect.Effect Node.Buffer.Buffer
bufferSlice start end buf = Effect.Uncurried.runEffectFn3 bufferSliceImpl start end buf

bufferConcat :: Array Node.Buffer.Buffer -> Effect.Effect Node.Buffer.Buffer
bufferConcat = Effect.Uncurried.runEffectFn1 bufferConcatImpl

bufferSize :: Node.Buffer.Buffer -> Effect.Effect Int
bufferSize = Effect.Uncurried.runEffectFn1 bufferSizeImpl

encryptAes256GcmRaw :: Node.Buffer.Buffer -> Node.Buffer.Buffer -> Node.Buffer.Buffer -> Effect.Effect { ciphertext :: Node.Buffer.Buffer, authTag :: Node.Buffer.Buffer }
encryptAes256GcmRaw key iv plaintext = Effect.Uncurried.runEffectFn3 encryptAes256GcmRawImpl key iv plaintext

decryptAes256GcmRaw :: Node.Buffer.Buffer -> Node.Buffer.Buffer -> Node.Buffer.Buffer -> Node.Buffer.Buffer -> Effect.Effect Node.Buffer.Buffer
decryptAes256GcmRaw key iv authTag ciphertext = Effect.Uncurried.runEffectFn4 decryptAes256GcmRawImpl key iv authTag ciphertext

sha256Hash :: String -> Effect.Effect String
sha256Hash = Effect.Uncurried.runEffectFn1 sha256HashImpl

canonicalJsonStringify :: Data.Argonaut.Core.Json -> Effect.Effect String
canonicalJsonStringify = Effect.Uncurried.runEffectFn1 canonicalJsonStringifyImpl

sha256HashBuffers :: Array Node.Buffer.Buffer -> Effect.Effect String
sha256HashBuffers = Effect.Uncurried.runEffectFn1 sha256HashBuffersImpl

encryptAes256Gcm :: String -> Node.Buffer.Buffer -> Effect.Effect Node.Buffer.Buffer
encryptAes256Gcm keyHex plaintext = do
  key <- bufferFromHex keyHex
  iv <- randomBytesBuffer ivLength
  { ciphertext, authTag } <- encryptAes256GcmRaw key iv plaintext
  bufferConcat [ iv, authTag, ciphertext ]

decryptAes256Gcm :: String -> Node.Buffer.Buffer -> Effect.Effect (Data.Either.Either String Node.Buffer.Buffer)
decryptAes256Gcm keyHex encryptedData = do
  result <- Effect.Exception.try do
    key <- bufferFromHex keyHex
    size <- bufferSize encryptedData
    iv <- bufferSlice 0 ivLength encryptedData
    authTag <- bufferSlice ivLength (ivLength + authTagLength) encryptedData
    ciphertext <- bufferSlice (ivLength + authTagLength) size encryptedData
    decryptAes256GcmRaw key iv authTag ciphertext
  pure $ case result of
    Data.Either.Left err -> Data.Either.Left (Effect.Exception.message err)
    Data.Either.Right buffer -> Data.Either.Right buffer
