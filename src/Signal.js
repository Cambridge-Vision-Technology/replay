// EffectFn2 - uncurried effectful function, no thunk wrapper
export const onSignalImpl = (signal, handler) => {
  process.on(signal, () => {
    handler();
  });
};

// EffectFn1 - handler receives error object
export const onUncaughtExceptionImpl = (handler) => {
  process.on("uncaughtException", (err) => {
    handler(err);
  });
};

// EffectFn1 - handler receives rejection reason (could be Error or any value)
export const onUnhandledRejectionImpl = (handler) => {
  process.on("unhandledRejection", (reason) => {
    handler(reason);
  });
};

// EffectFn1 - format error or value to string
export const formatErrorImpl = (err) => {
  if (err instanceof Error) {
    return err.stack || err.message || String(err);
  }
  return String(err);
};
