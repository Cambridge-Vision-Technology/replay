// FFI.Buffer - Node.js Buffer operations
// Note: EffectFn* expects uncurried functions that return directly (no thunk)

export const toStringImpl = (encoding, buffer) => buffer.toString(encoding);

export const fromStringImpl = (str, encoding) => Buffer.from(str, encoding);
