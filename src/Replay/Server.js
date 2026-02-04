import { WebSocketServer } from "ws";
import { createServer } from "http";
import { unlinkSync } from "fs";

// Create server listening on a TCP port
export const createServerImpl = (port, onConnection, onError) => {
  const wss = new WebSocketServer({ port });

  wss.on("connection", (ws) => {
    onConnection(ws)();
  });

  wss.on("error", (err) => {
    onError(err.message)();
  });

  return wss;
};

// Create server listening on a Unix socket path
// onReady callback is called with the server when listening starts
export const createServerOnSocketImpl = (
  socketPath,
  onConnection,
  onReady,
  onError,
) => {
  // Remove existing socket file if it exists (ignore errors)
  try {
    unlinkSync(socketPath);
  } catch {
    // Socket file doesn't exist or cannot be removed - continue
  }

  // Create HTTP server that listens on Unix socket
  const httpServer = createServer();

  const wss = new WebSocketServer({ server: httpServer });

  // Capture the upgrade request and attach it to the WebSocket
  // This is needed because modern ws versions don't store upgradeReq
  wss.on("connection", (ws, req) => {
    ws._upgradeReq = req;
    onConnection(ws)();
  });

  wss.on("error", (err) => {
    onError(err.message)();
  });

  httpServer.on("error", (err) => {
    onError(err.message)();
  });

  // Store httpServer reference for cleanup
  wss._httpServer = httpServer;
  wss._socketPath = socketPath;

  // Listen on Unix socket - only call onReady after binding succeeds
  httpServer.listen(socketPath, () => {
    onReady(wss)();
  });

  return wss;
};

export const closeServerImpl = (wss) => {
  wss.close();

  // Clean up Unix socket if applicable (ignore errors)
  wss._httpServer?.close();
  try {
    unlinkSync(wss._socketPath);
  } catch {
    // Socket path not set or cannot be removed - continue
  }
};

export const onMessageImpl = (ws, callback) => {
  ws.on("message", (data) => {
    callback(data.toString())();
  });
};

export const onCloseImpl = (ws, callback) => {
  ws.on("close", () => {
    callback();
  });
};

// Safe send that checks readyState before sending
// Returns { success: true } or { success: false, error: "..." }
// NOTE: readyState check is WebSocket protocol requirement, not business logic
/* eslint-disable purescript-ffi/no-logic-in-ffi */
export const sendSafeImpl = (ws, message) => {
  if (ws.readyState !== 1) {
    return {
      success: false,
      error: "Connection not open (state: " + ws.readyState + ")",
    };
  }
  try {
    ws.send(message);
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
};
/* eslint-enable purescript-ffi/no-logic-in-ffi */

// Generate a unique ID for a WebSocket connection
// We attach an ID to the connection object if it doesn't have one
let connectionIdCounter = 0;
export const getConnectionIdImpl = (ws) => {
  ws._platformConnId ??= `conn-${connectionIdCounter++}`;
  return ws._platformConnId;
};

// Extract raw URL from WebSocket connection upgrade request
// Returns the URL string or null if not available
// Query string parsing is done in PureScript
export const getConnectionUrlImpl = (ws) => {
  const req = ws._upgradeReq ?? ws.upgradeReq ?? ws._req;
  return req?.url ?? null;
};
