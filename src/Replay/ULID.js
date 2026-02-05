import { ulid, decodeTime } from "ulid";

export const generateImpl = () => ulid();

export const generateAtImpl = (timestamp) => ulid(timestamp);

export const decodeTimeImpl = (ulidStr) => decodeTime(ulidStr);
