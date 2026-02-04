# Echo Client

Demo application demonstrating replay harness integration for HTTP requests.

## Usage

### Direct HTTP (no harness)

When `PLATFORM_URL` is not set, the client makes direct HTTP requests:

```bash
nix run .#echo-client -- "hello world"
```

This sends a POST request to `https://httpbin.org/anything` with the message in the body and prints the response JSON.

### Via Replay Harness

When `PLATFORM_URL` is set to a Unix socket path, the client routes HTTP requests through the replay WebSocket:

```bash
# In terminal 1: Start the harness in passthrough mode
nix run .#default -- --mode passthrough --socket /tmp/replay.sock

# In terminal 2: Run the client
PLATFORM_URL=/tmp/replay.sock nix run .#echo-client -- "hello via harness"
```

### Recording Mode

To record HTTP interactions for later playback:

```bash
# Start harness in record mode
nix run .#default -- --mode record --socket /tmp/replay.sock --recording-path ./recording.json

# Run the client (interactions are recorded)
PLATFORM_URL=/tmp/replay.sock nix run .#echo-client -- "hello for recording"

# Stop the harness (Ctrl+C) to save the recording
```

### Playback Mode

To replay recorded interactions:

```bash
# Start harness in playback mode
nix run .#default -- --mode playback --socket /tmp/replay.sock --recording-path ./recording.json

# Run the client (uses recorded responses)
PLATFORM_URL=/tmp/replay.sock nix run .#echo-client -- "hello for recording"
```

## Exit Codes

- `0` - Success
- `1` - Error (usage error, HTTP error, or harness connection failure)

## Protocol

The echo-client demonstrates the replay protocol:

1. Connects to harness via WebSocket (Unix socket)
2. Sends a `CommandOpen` with service `"http"` and payload containing method, url, body, headers
3. Receives an `EventClose` with service `"http"` and payload containing statusCode, body
4. Prints the response body and exits
