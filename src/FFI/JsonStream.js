// FFI.JsonStream - Streaming JSON parser for large arrays
// Parses JSON arrays without blocking the event loop by processing in chunks
// and yielding control via setImmediate between chunks.

// Note: We cannot import yieldToEventLoop from EventLoop.js because PureScript's
// FFI system copies each module's foreign.js to its own directory during the build.
// Relative imports between FFI files don't work. This duplication is intentional.
// See EventLoop.js for the canonical implementation with full documentation.
function yieldToEventLoop() {
  return new Promise((resolve) => setImmediate(resolve));
}

/**
 * Parse a recording JSON object in a streaming manner.
 * Extracts metadata fields synchronously (they're small) but parses the
 * messages array using the streaming parser to avoid blocking.
 *
 * This prevents blocking the event loop when loading large recording files.
 *
 * @param {Buffer} buffer - The buffer containing the recording JSON data
 * @returns {() => Promise<{schemaVersion: number, scenarioName: string, recordedAt: string, messages: Array}>}
 */
export const parseRecordingStreamImpl = (buffer) => () => {
  return parseRecordingInChunks(buffer.toString("utf8"));
};

/**
 * Parse a recording JSON string in a streaming manner.
 * Extracts metadata synchronously, then streams the messages array.
 *
 * @param {string} jsonString - The JSON string to parse
 * @returns {Promise<{schemaVersion: number, scenarioName: string, recordedAt: string, messages: Array}>}
 */
async function parseRecordingInChunks(jsonString) {
  // Find the positions of all top-level fields without fully parsing
  const fieldPositions = findObjectFieldPositions(jsonString);

  // Extract metadata fields (small, safe to parse synchronously)
  const schemaVersion = extractFieldValue(
    jsonString,
    fieldPositions,
    "schemaVersion",
  );
  const scenarioName = extractFieldValue(
    jsonString,
    fieldPositions,
    "scenarioName",
  );
  const recordedAt = extractFieldValue(
    jsonString,
    fieldPositions,
    "recordedAt",
  );

  if (schemaVersion === undefined) {
    throw new Error("Missing required field: schemaVersion");
  }
  if (scenarioName === undefined) {
    throw new Error("Missing required field: scenarioName");
  }
  if (recordedAt === undefined) {
    throw new Error("Missing required field: recordedAt");
  }

  // Get the messages array field position
  const messagesField = fieldPositions.messages;
  if (!messagesField) {
    throw new Error("Missing required field: messages");
  }

  // Extract just the messages array substring and parse it with streaming
  const messagesArrayStr = jsonString.slice(
    messagesField.valueStart,
    messagesField.valueEnd,
  );
  const messages = await parseArrayInChunks(messagesArrayStr);

  return {
    schemaVersion,
    scenarioName,
    recordedAt,
    messages,
  };
}

/**
 * Find the positions of all top-level fields in a JSON object.
 * Returns an object mapping field names to their value positions.
 *
 * @param {string} jsonString - The JSON string containing an object
 * @returns {Object<string, {valueStart: number, valueEnd: number}>}
 */
function findObjectFieldPositions(jsonString) {
  const positions = {};
  let pos = 0;
  const len = jsonString.length;

  // Skip whitespace to find opening brace
  while (pos < len && /\s/.test(jsonString[pos])) {
    pos++;
  }

  if (pos >= len || jsonString[pos] !== "{") {
    throw new Error("Expected JSON object starting with '{'");
  }
  pos++; // Skip the opening brace

  while (pos < len) {
    // Skip whitespace
    while (pos < len && /\s/.test(jsonString[pos])) {
      pos++;
    }

    if (pos >= len) break;

    // Check for end of object
    if (jsonString[pos] === "}") {
      break;
    }

    // Skip comma between fields
    if (jsonString[pos] === ",") {
      pos++;
      continue;
    }

    // Expect a string key
    if (jsonString[pos] !== '"') {
      throw new Error(
        `Expected string key at position ${pos}, found '${jsonString[pos]}'`,
      );
    }

    // Parse the field name
    const keyStart = pos + 1;
    pos++; // Skip opening quote
    while (pos < len && jsonString[pos] !== '"') {
      if (jsonString[pos] === "\\") {
        pos += 2; // Skip escaped character
      } else {
        pos++;
      }
    }
    const keyEnd = pos;
    const fieldName = jsonString.slice(keyStart, keyEnd);
    pos++; // Skip closing quote

    // Skip whitespace and colon
    while (pos < len && /\s/.test(jsonString[pos])) {
      pos++;
    }
    if (jsonString[pos] !== ":") {
      throw new Error(`Expected ':' after field name at position ${pos}`);
    }
    pos++; // Skip colon

    // Skip whitespace before value
    while (pos < len && /\s/.test(jsonString[pos])) {
      pos++;
    }

    // Find the value boundaries
    const valueStart = pos;
    const valueEnd = findValueEnd(jsonString, pos);
    pos = valueEnd;

    positions[fieldName] = { valueStart, valueEnd };
  }

  return positions;
}

/**
 * Find the end position of a JSON value starting at the given position.
 *
 * @param {string} jsonString - The JSON string
 * @param {number} start - Starting position of the value
 * @returns {number} - End position (exclusive)
 */
function findValueEnd(jsonString, start) {
  let pos = start;
  const len = jsonString.length;
  const char = jsonString[pos];

  // String value
  if (char === '"') {
    pos++; // Skip opening quote
    while (pos < len) {
      if (jsonString[pos] === "\\") {
        pos += 2;
      } else if (jsonString[pos] === '"') {
        pos++; // Include closing quote
        break;
      } else {
        pos++;
      }
    }
    return pos;
  }

  // Array or object - track nesting
  if (char === "[" || char === "{") {
    const closeChar = char === "[" ? "]" : "}";
    let depth = 1;
    let inString = false;
    let escaped = false;
    pos++;

    while (pos < len && depth > 0) {
      const c = jsonString[pos];

      if (escaped) {
        escaped = false;
        pos++;
        continue;
      }

      if (inString) {
        if (c === "\\") {
          escaped = true;
        } else if (c === '"') {
          inString = false;
        }
        pos++;
        continue;
      }

      if (c === '"') {
        inString = true;
      } else if (c === "[" || c === "{") {
        depth++;
      } else if (c === "]" || c === "}") {
        depth--;
      }
      pos++;
    }
    return pos;
  }

  // Number, boolean, or null - find the end
  while (pos < len) {
    const c = jsonString[pos];
    if (c === "," || c === "}" || c === "]" || /\s/.test(c)) {
      break;
    }
    pos++;
  }
  return pos;
}

/**
 * Extract and parse a field value from the JSON string.
 *
 * @param {string} jsonString - The full JSON string
 * @param {Object} positions - Field positions from findObjectFieldPositions
 * @param {string} fieldName - Name of the field to extract
 * @returns {*} - Parsed value, or undefined if field not found
 */
function extractFieldValue(jsonString, positions, fieldName) {
  const field = positions[fieldName];
  if (!field) {
    return undefined;
  }
  const valueStr = jsonString.slice(field.valueStart, field.valueEnd);
  return JSON.parse(valueStr);
}

/**
 * Parse a JSON array from a buffer in a streaming/chunked manner.
 * This implementation processes array elements in batches and yields
 * control to the event loop between batches to prevent blocking.
 *
 * @param {Buffer} buffer - The buffer containing JSON array data
 * @returns {() => Promise<Array>} - Effect that returns Promise resolving to parsed array
 */
export const parseArrayStreamImpl = (buffer) => () => {
  return new Promise((resolve, reject) => {
    try {
      // Convert buffer to string
      const jsonString = buffer.toString("utf8");

      // Parse the JSON structure - we need to find array element boundaries
      // without fully parsing everything at once
      const result = parseArrayInChunks(jsonString);
      resolve(result);
    } catch (err) {
      reject(err);
    }
  });
};

/**
 * Parse a JSON array in chunks, yielding to the event loop periodically.
 * This prevents long-running parse operations from blocking.
 *
 * @param {string} jsonString - The JSON string to parse
 * @returns {Promise<Array>} - Promise resolving to the parsed array
 */
async function parseArrayInChunks(jsonString) {
  // Find array boundaries while yielding periodically
  const boundaries = await findArrayElementBoundaries(jsonString);

  if (boundaries.length === 0) {
    // Empty array or not an array
    const parsed = JSON.parse(jsonString);
    if (!Array.isArray(parsed)) {
      throw new Error("Input is not a JSON array");
    }
    return parsed;
  }

  // Parse elements in small chunks, yielding between chunks
  // Balance between performance and event loop responsiveness
  // With 50 elements per chunk, we yield ~20 times for 1000 elements
  // Each yield takes ~1-4ms, so total overhead is ~20-80ms
  const chunkSize = 50;
  const results = [];

  for (let i = 0; i < boundaries.length; i += chunkSize) {
    const end = Math.min(i + chunkSize, boundaries.length);

    for (let j = i; j < end; j++) {
      const { start, end: elemEnd } = boundaries[j];
      const elementStr = jsonString.slice(start, elemEnd);
      results.push(JSON.parse(elementStr));
    }

    // Yield to the event loop after each chunk
    // This allows pending setInterval and setImmediate callbacks to run
    await yieldToEventLoop();
  }

  return results;
}

/**
 * Find the start and end positions of each top-level element in a JSON array.
 * This scans the string character by character, tracking nesting depth.
 *
 * @param {string} jsonString - The JSON string containing an array
 * @returns {Promise<Array<{start: number, end: number}>>} - Element boundaries
 */
async function findArrayElementBoundaries(jsonString) {
  const boundaries = [];
  let pos = 0;
  const len = jsonString.length;

  // Skip whitespace to find opening bracket
  while (pos < len && /\s/.test(jsonString[pos])) {
    pos++;
  }

  if (pos >= len || jsonString[pos] !== "[") {
    throw new Error("Expected JSON array starting with '['");
  }
  pos++; // Skip the opening bracket

  // Skip whitespace after opening bracket
  while (pos < len && /\s/.test(jsonString[pos])) {
    pos++;
  }

  // Check for empty array
  if (pos < len && jsonString[pos] === "]") {
    return boundaries;
  }

  // Yield counter - yield to event loop periodically during scanning
  // We yield every 10k characters to ensure the event loop remains responsive
  // during large file parsing. This allows timer callbacks to run.
  let yieldCounter = 0;
  const yieldInterval = 10000; // Yield every 10k characters scanned

  // Process each element
  while (pos < len) {
    // Skip whitespace
    while (pos < len && /\s/.test(jsonString[pos])) {
      pos++;
    }

    if (pos >= len) break;

    // Check for end of array
    if (jsonString[pos] === "]") {
      break;
    }

    // Find the start of this element
    const elementStart = pos;

    // Track nesting to find the end of this element
    let depth = 0;
    let inString = false;
    let escaped = false;

    while (pos < len) {
      const char = jsonString[pos];

      if (escaped) {
        escaped = false;
        pos++;
        yieldCounter++;
        continue;
      }

      if (inString) {
        if (char === "\\") {
          escaped = true;
        } else if (char === '"') {
          inString = false;
        }
        pos++;
        yieldCounter++;
        continue;
      }

      // Not in string
      switch (char) {
        case '"':
          inString = true;
          break;
        case "{":
        case "[":
          depth++;
          break;
        case "}":
          if (depth > 0) {
            depth--;
          }
          break;
        case "]":
          if (depth > 0) {
            depth--;
          }
          // If depth is 0 and we see ], we've hit the end of the array
          // Don't advance pos - let the outer loop handle it
          break;
        case ",":
          if (depth === 0) {
            // Found end of element
            boundaries.push({ start: elementStart, end: pos });
            pos++; // Skip the comma
            // Yield periodically
            if (yieldCounter >= yieldInterval) {
              await yieldToEventLoop();
              yieldCounter = 0;
            }
            // Continue to next element (outer loop)
            break;
          }
          break;
        default:
          break;
      }

      // If we found a comma at depth 0, we've already pushed and incremented
      if (depth === 0 && char === ",") {
        break;
      }

      // If we hit ] at depth 0, we've reached the end of the array
      // Don't advance pos, break to handle the last element
      if (depth === 0 && char === "]") {
        break;
      }

      pos++;
      yieldCounter++;

      // Yield periodically during large scans
      if (yieldCounter >= yieldInterval) {
        await yieldToEventLoop();
        yieldCounter = 0;
      }
    }

    // If we exited without finding a comma, check if we're at the end
    if (pos >= len || jsonString[pos] === "]") {
      // This is the last element
      // Find where it actually ends (backtrack from pos to skip whitespace)
      let endPos = pos;
      // Go back to before any trailing whitespace
      while (endPos > elementStart && /\s/.test(jsonString[endPos - 1])) {
        endPos--;
      }
      // If we're at ']', the element ends just before it
      if (jsonString[pos] === "]") {
        endPos = pos;
        // Backtrack to skip trailing whitespace before the ]
        while (endPos > elementStart && /\s/.test(jsonString[endPos - 1])) {
          endPos--;
        }
      }
      if (endPos > elementStart) {
        boundaries.push({ start: elementStart, end: endPos });
      }
      break;
    }
  }

  return boundaries;
}
