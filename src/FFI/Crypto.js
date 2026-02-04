import crypto from "node:crypto";
import stringify from "json-stable-stringify";

export const md5HashImpl = (input) => {
  return crypto.createHash("md5").update(input).digest("hex");
};

export const randomBytesImpl = (numBytes) => {
  return crypto.randomBytes(numBytes).toString("hex");
};

export const sha256HashImpl = (input) =>
  crypto.createHash("sha256").update(input).digest("hex");

export const canonicalJsonStringifyImpl = (obj) => stringify(obj);

export const sha256HashBuffersImpl = (buffers) =>
  crypto.createHash("sha256").update(Buffer.concat(buffers)).digest("hex");

export const randomBytesBufferImpl = (numBytes) => crypto.randomBytes(numBytes);

export const bufferFromHexImpl = (hexString) => Buffer.from(hexString, "hex");

export const bufferSliceImpl = (start, end, buffer) =>
  buffer.subarray(start, end);

export const bufferConcatImpl = (buffers) => Buffer.concat(buffers);

export const bufferSizeImpl = (buffer) => buffer.length;

export const encryptAes256GcmRawImpl = (keyBuffer, ivBuffer, plaintext) => {
  const cipher = crypto.createCipheriv("aes-256-gcm", keyBuffer, ivBuffer);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return { ciphertext, authTag };
};

export const decryptAes256GcmRawImpl = (
  keyBuffer,
  ivBuffer,
  authTagBuffer,
  ciphertext,
) => {
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuffer, ivBuffer);
  decipher.setAuthTag(authTagBuffer);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
};
