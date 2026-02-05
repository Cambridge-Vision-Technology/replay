# Plan: Issue #5 - Lazy Message Loading for Large Recordings

## Problem

When loading large recording files (100MB+), synchronous JSON parsing and message decoding blocks Node.js's event loop, causing timeouts in parallel test scenarios.

### Root Cause

The recording loading pipeline has synchronous bottlenecks:

| Stage | Implementation | Blocks Event Loop? |
|-------|---------------|-------------------|
| File read | `Aff` (async) | No |
| Zstd decompress | `zstdDecompressAsync` | No |
| **JSON parsing** | `parseJson` (pure/sync) | **Yes** |
| **Decode messages** | `traverse decodeRecordedMessage` | **Yes** |
| **Build hash index** | `buildHashIndex` (eager) | **Yes** |

## Solution

Implement **Lazy Message Loading** - parse only recording metadata upfront, store raw JSON for each message, and deserialize on-demand when hash matches.

---

## Tasks

### Task 1: Add streaming JSON parser dependency
- [ ] **Status**: Pending

**What**: Add a streaming JSON parser (like `clarinet` or `stream-json`) via FFI

**Verifiable by**: Parser can be imported and used in PureScript via FFI

**BDD Test**:
```gherkin
Feature: Streaming JSON parsing
  Scenario: Parse large JSON without blocking
    Given a 50MB JSON file containing an array of 1000 objects
    When I parse the file using the streaming parser
    Then the event loop should remain responsive (heartbeat messages continue)
    And all objects should be parsed correctly
```

**Files to create/modify**:
- `src/FFI/JsonStream.js` (new) - JavaScript FFI implementation
- `src/FFI/JsonStream.purs` (new) - PureScript bindings

---

### Task 2: Create lazy recording loader
- [ ] **Status**: Pending

**What**: Create `loadRecordingLazy` that only parses metadata and builds a position index without fully decoding all messages

**Verifiable by**: Loading a 100MB recording completes in under 1 second without blocking

**BDD Test**:
```gherkin
Feature: Lazy recording loading
  Scenario: Load large recording without event loop blocking
    Given a compressed recording file with 90 messages totaling 100MB
    When I start loading the recording
    And simultaneously send 10 heartbeat messages at 100ms intervals
    Then all heartbeat responses should arrive within 200ms of sending
    And the recording metadata should be available
```

**Files to modify**:
- `src/Replay/Recording.purs` - Add `loadRecordingLazy` function
- `src/Replay/Recording.purs` - Add `LazyRecording` type

---

### Task 3: Implement on-demand message decoding
- [ ] **Status**: Pending

**What**: Messages are stored as raw JSON strings and decoded only when accessed via hash lookup

**Verifiable by**: Memory usage stays low until messages are actually requested

**BDD Test**:
```gherkin
Feature: On-demand message decoding
  Scenario: Messages decoded only when needed
    Given a lazily loaded recording with 90 messages
    When I request playback of a specific hash
    Then only the matching message should be decoded
    And memory usage should be proportional to decoded messages only
```

**Files to modify**:
- `src/Replay/Recording.purs` - Add `LazyMessage` type with raw JSON storage
- `src/Replay/Recording.purs` - Add `decodeMessageOnDemand` function

---

### Task 4: Implement chunked hash index building
- [ ] **Status**: Pending

**What**: Build hash index in chunks with event loop yields between chunks (using `setImmediate` or similar)

**Verifiable by**: Hash index building doesn't block for more than 10ms at a time

**BDD Test**:
```gherkin
Feature: Non-blocking hash index building
  Scenario: Build index while remaining responsive
    Given a recording with 1000 messages
    When building the hash index
    And sending heartbeat messages every 50ms
    Then all heartbeats should receive responses within 100ms
```

**Files to modify**:
- `src/Replay/Recording.purs` - Modify `buildHashIndex` to be chunked/async
- `src/FFI/EventLoop.js` (new) - FFI for `setImmediate`/yielding
- `src/FFI/EventLoop.purs` (new) - PureScript bindings

---

### Task 5: Update Player to use lazy loading
- [ ] **Status**: Pending

**What**: Modify Player module to work with LazyRecording type

**Verifiable by**: Playback works correctly with lazy-loaded recordings

**BDD Test**:
```gherkin
Feature: Player with lazy loading
  Scenario: Playback from lazy-loaded recording
    Given a lazily loaded recording with 50 messages
    When a client sends a request matching a recorded hash
    Then the correct response should be returned
    And only the matched message should be fully decoded
```

**Files to modify**:
- `src/Replay/Player.purs` - Update to accept `LazyRecording`
- `src/Replay/Player.purs` - Modify `findMatch` to decode on-demand

---

### Task 6: Integration test with parallel sessions
- [ ] **Status**: Pending

**What**: Verify the fix resolves the original issue - parallel sessions with large recordings don't cause timeouts

**Verifiable by**: No timeout errors when running 8 parallel test workers with large recordings

**BDD Test**:
```gherkin
Feature: Parallel playback sessions with large recordings
  Scenario: Multiple concurrent sessions with 100MB recordings
    Given 4 separate recording files of approximately 25MB each
    When 4 playback sessions are started simultaneously
    And each session makes 10 requests within 5 seconds
    Then all sessions should complete without timeout errors
    And all responses should be correct
```

**Files to create**:
- `test/features/parallel_large_recordings.feature` (new)
- Test fixtures with appropriately sized recordings

---

### Task 7: Backwards compatibility verification
- [ ] **Status**: Pending

**What**: Ensure existing recording format works without changes and all existing tests pass

**Verifiable by**: All existing tests pass with new lazy loader

**BDD Test**:
```gherkin
Feature: Backwards compatibility
  Scenario: Existing recordings work with lazy loader
    Given a recording created with the previous version
    When loaded with the new lazy loader
    Then playback should work identically to before
    And all existing tests should pass
```

**Verification**: Run `nix flake check` - all tests must pass

---

## Implementation Order

```
Task 1 (Streaming JSON FFI)
    ↓
Task 2 (Lazy Recording Loader)
    ↓
Task 3 (On-demand Message Decoding)
    ↓
Task 4 (Chunked Hash Index)
    ↓
Task 5 (Update Player)
    ↓
Task 6 & Task 7 (Integration & Compatibility - can run in parallel)
```

## Key Files Summary

| File | Action | Purpose |
|------|--------|---------|
| `src/FFI/JsonStream.js` | Create | Streaming JSON parser FFI |
| `src/FFI/JsonStream.purs` | Create | PureScript bindings |
| `src/FFI/EventLoop.js` | Create | Event loop yield FFI |
| `src/FFI/EventLoop.purs` | Create | PureScript bindings |
| `src/Replay/Recording.purs` | Modify | Add lazy loading types and functions |
| `src/Replay/Player.purs` | Modify | Use lazy recordings |

## Risk Considerations

1. **Memory mapping**: May need to keep file handles open longer for on-demand access
2. **Error handling**: Deferred parsing means deferred error discovery - need good error messages
3. **Hash computation**: May need to compute/extract hashes during streaming phase
4. **Type changes**: `LazyRecording` vs `Recording` - need to maintain compatibility or migrate

## Success Criteria

- [ ] Large recordings (100MB+) load without blocking event loop for >10ms
- [ ] Parallel test sessions don't experience timeout errors
- [ ] Memory usage proportional to accessed messages, not total recording size
- [ ] All existing tests continue to pass
- [ ] No breaking changes to recording file format
