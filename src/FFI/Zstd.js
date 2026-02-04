import { promisify } from "util";
import { zstdCompress, zstdDecompress } from "zlib";

const zstdCompressAsync = promisify(zstdCompress);
const zstdDecompressAsync = promisify(zstdDecompress);

export const compressImpl = (buffer) => () => zstdCompressAsync(buffer);

export const decompressImpl = (buffer) => () => zstdDecompressAsync(buffer);
