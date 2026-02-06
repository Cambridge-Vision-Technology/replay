// FFI.EventLoop - Event loop yielding for non-blocking async operations
// Provides setImmediate-based yielding to prevent blocking the Node.js event loop
// during long-running synchronous operations like hash index building.

/**
 * Build a hash index from an array of raw JSON messages in chunks.
 * Processes messages in batches and yields to the event loop between batches
 * to prevent blocking.
 *
 * @param {number} chunkSize - Number of messages to process per chunk
 * @param {Array<object>} messages - Array of raw JSON message objects
 * @returns {() => Promise<Object>} - Effect that returns Promise resolving to hash index
 *
 * The returned hash index is a plain JavaScript object where:
 * - Keys are hash strings
 * - Values are arrays of {index, message} objects (to handle duplicate hashes)
 */
export const buildHashIndexChunkedImpl = (chunkSize) => (messages) => () => {
  return buildHashIndexInChunks(messages, chunkSize);
};

/**
 * Internal function that builds the hash index in chunks with event loop yields.
 *
 * @param {Array<object>} messages - Array of raw JSON message objects
 * @param {number} chunkSize - Number of messages to process per chunk
 * @returns {Promise<Object>} - Promise resolving to hash index object
 */
async function buildHashIndexInChunks(messages, chunkSize) {
  const hashIndex = {};

  for (let i = 0; i < messages.length; i += chunkSize) {
    const end = Math.min(i + chunkSize, messages.length);

    // Process this chunk of messages
    for (let j = i; j < end; j++) {
      const message = messages[j];
      const hash = extractHash(message);

      if (hash !== null) {
        // Add to index - store both the index and the raw message
        if (!hashIndex[hash]) {
          hashIndex[hash] = [];
        }
        hashIndex[hash].push({
          index: j,
          message: message,
        });
      }
    }

    // Yield to the event loop after each chunk to prevent blocking
    // This allows timers, I/O callbacks, and other operations to run
    await yieldToEventLoop();
  }

  return hashIndex;
}

/**
 * Extract the hash field from a raw JSON message object.
 * Returns null if the hash field is missing or null.
 *
 * The hash field in the JSON is always either:
 * - A plain string (when the PureScript `Maybe String` was `Just value`)
 * - `null` (when the PureScript `Maybe String` was `Nothing`)
 *
 * This is because PureScript's Argonaut library encodes `Maybe` values as
 * plain JSON values (not wrapped objects). We don't need to handle
 * PureScript's internal Maybe representation (like `{ value0: ... }`)
 * because that representation is never serialized to JSON.
 *
 * @param {object} message - Raw JSON message object
 * @returns {string|null} - The hash string or null
 */
function extractHash(message) {
  if (message && typeof message === "object" && "hash" in message) {
    const hash = message.hash;
    if (typeof hash === "string") {
      return hash;
    }
  }
  return null;
}

/**
 * Yield control to the event loop.
 * Uses setImmediate which schedules the callback for the check phase,
 * allowing other pending operations to run.
 *
 * @returns {Promise<void>}
 */
export function yieldToEventLoop() {
  return new Promise((resolve) => setImmediate(resolve));
}
