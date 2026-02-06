# replay

WebSocket-based recording/playback harness for deterministic testing of external effects.

## Lazy Loading

For large recording files (100MB+), synchronous JSON parsing can block the Node.js event loop and cause timeouts in parallel test scenarios. The lazy loading API addresses this by:

1. Parsing recording metadata upfront (small and fast)
2. Storing messages as raw JSON until explicitly needed
3. Decoding messages on-demand when hash lookups match
4. Yielding to the event loop during processing to prevent blocking

### When to Use

- `loadRecording`: Standard loader. Parses and decodes all messages upfront. Use for small recordings or when you need immediate access to all messages.
- `loadRecordingLazy`: Non-blocking loader. Parses messages in chunks with event loop yields. Use for large recordings or parallel test scenarios.

### Performance Characteristics

| Operation        | Complexity | Notes                                                       |
| ---------------- | ---------- | ----------------------------------------------------------- |
| Loading          | O(n)       | Processes messages in chunks of 50, yielding between chunks |
| Hash index build | O(n)       | Non-blocking, chunked processing                            |
| Hash lookup      | O(1)       | Direct index access                                         |
| Message decode   | O(1)       | Only matched messages are decoded                           |

### PureScript API

```purescript
import Replay.Recording (loadRecordingLazy, buildHashIndexChunked, LazyRecording, LazyHashIndex)
import Replay.Player (createLazyPlayerState, findMatchLazy, LazyPlayerState)

-- Load recording without blocking event loop
loadRecordingLazy :: String -> Aff (Either String LazyRecording)

-- Build hash index in chunks (non-blocking)
buildHashIndexChunked :: LazyRecording -> Aff LazyHashIndex

-- Create player state from lazy recording
createLazyPlayerState :: LazyRecording -> LazyHashIndex -> Effect LazyPlayerState

-- Find message by hash (O(1) lookup, on-demand decode)
findMatchLazy :: String -> LazyPlayerState -> Effect (Maybe (Tuple Int RecordedMessage))
```

### JavaScript API

```javascript
import * as Recording from "./output/Replay.Recording/index.js";
import * as Player from "./output/Replay.Player/index.js";

// Load recording (returns Effect that produces Promise)
const result = await Recording.loadRecordingLazyJs(path)();

// Handle Either result
if (result.constructor.name === "Right") {
  const lazyRecording = result.value0;

  // Build hash index (non-blocking)
  const hashIndex = await Recording.buildHashIndexChunkedJs(lazyRecording)();

  // Create player state
  const playerState = Player.createLazyPlayerState(lazyRecording)(hashIndex)();

  // Find message by hash (O(1) lookup)
  const match = Player.findMatchLazy(hashKey)(playerState)();
  if (match.constructor.name === "Just") {
    const [index, message] = [match.value0.value0, match.value0.value1];
  }
} else {
  console.error("Load failed:", result.value0);
}
```

### Memory Usage

Messages remain as raw JSON until decoded. Only matched messages consume full decode memory:

```
1000 messages, 1 lookup  -> ~0.6 MB (only 1 message decoded)
1000 messages, all decoded -> ~90 MB (all messages in memory)
```
