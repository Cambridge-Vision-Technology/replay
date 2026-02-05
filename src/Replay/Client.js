import WebSocket from "ws";
import { connect } from "net";

// Connect to WebSocket via TCP (ws:// or wss://)
export const connectImpl = (url, onOpen, onError) => {
  const ws = new WebSocket(url);

  ws.on("open", () => {
    onOpen(ws)();
  });

  ws.on("error", (err) => {
    const message =
      err.message || err.code || err.cause?.message || String(err);
    onError(message)();
  });

  return ws;
};

// Connect to WebSocket via Unix socket
// NOTE: The socketPath option doesn't work reliably in ws v8.x
// Instead, we use createConnection to create the underlying socket
export const connectToSocketImpl = (socketPath, onOpen, onError) => {
  const ws = new WebSocket("ws://unix-socket/", {
    createConnection: () => connect(socketPath),
  });

  ws.on("open", () => {
    onOpen(ws)();
  });

  ws.on("error", (err) => {
    const message =
      err.message || err.code || err.cause?.message || String(err);
    onError(message)();
  });

  return ws;
};

// Connect to WebSocket via Unix socket with a session ID
// The session ID is passed as a query parameter in the WebSocket URL
// The server extracts this from the upgrade request to route messages to the correct session
export const connectToSocketWithSessionImpl = (
  socketPath,
  sessionId,
  onOpen,
  onError,
) => {
  const encodedSessionId = encodeURIComponent(sessionId);
  const ws = new WebSocket(`ws://unix-socket/?session=${encodedSessionId}`, {
    createConnection: () => connect(socketPath),
  });

  ws.on("open", () => {
    onOpen(ws)();
  });

  ws.on("error", (err) => {
    const message =
      err.message || err.code || err.cause?.message || String(err);
    onError(message)();
  });

  return ws;
};

export const disconnectImpl = (ws) => {
  ws.close();
};

export const sendImpl = (ws, message) => {
  ws.send(message);
};

export const onMessageImpl = (ws, callback) => {
  ws.on("message", (data) => {
    callback(data.toString())();
  });
};
