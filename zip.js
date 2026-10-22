// Minimal zip support for the browser front end, for exporting and importing save data: writing uses no
// compression (stored entries); reading accepts stored and deflated entries (deflate through DecompressionStream).
"use strict";
const CrankedZip = (() => {
  const CRC = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; CRC[n] = c >>> 0; }
  function crc32(data) { let c = 0xFFFFFFFF; for (let i = 0; i < data.length; i++) c = CRC[(c ^ data[i]) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }

  // files: [{ path, data: Uint8Array }] -> Uint8Array of a zip file
  function write(files) {
    const enc = new TextEncoder(), parts = [], central = [];
    let offset = 0;
    for (const f of files) {
      const name = enc.encode(f.path), crc = crc32(f.data), size = f.data.length;
      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034b50, true); local.setUint16(4, 20, true); local.setUint16(6, 0x0800, true); // UTF-8 names
      local.setUint32(14, crc, true); local.setUint32(18, size, true); local.setUint32(22, size, true);
      local.setUint16(26, name.length, true);
      parts.push(new Uint8Array(local.buffer), name, f.data);
      const c = new DataView(new ArrayBuffer(46));
      c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
      c.setUint32(16, crc, true); c.setUint32(20, size, true); c.setUint32(24, size, true);
      c.setUint16(28, name.length, true); c.setUint32(42, offset, true);
      central.push(new Uint8Array(c.buffer), name);
      offset += 30 + name.length + size;
    }
    let centralSize = 0; for (const p of central) centralSize += p.length;
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
    end.setUint32(12, centralSize, true); end.setUint32(16, offset, true);
    const all = [...parts, ...central, new Uint8Array(end.buffer)];
    const out = new Uint8Array(offset + centralSize + 22); let at = 0;
    for (const p of all) { out.set(p, at); at += p.length; }
    return out;
  }

  async function inflate(data) {
    const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  // Uint8Array of a zip file -> [{ path, data }] (folders left out); throws on anything it cannot read
  async function read(bytes) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength), dec = new TextDecoder();
    let end = -1;
    for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 65535); i--)
      if (view.getUint32(i, true) === 0x06054b50) { end = i; break; }
    if (end < 0) throw new Error("not a zip file");
    const count = view.getUint16(end + 10, true);
    let at = view.getUint32(end + 16, true);
    const files = [];
    for (let n = 0; n < count; n++) {
      if (at + 46 > bytes.length || view.getUint32(at, true) !== 0x02014b50) throw new Error("damaged zip file");
      const method = view.getUint16(at + 10, true), packed = view.getUint32(at + 20, true);
      const nameLength = view.getUint16(at + 28, true), extra = view.getUint16(at + 30, true), comment = view.getUint16(at + 32, true);
      const local = view.getUint32(at + 42, true);
      const path = dec.decode(bytes.subarray(at + 46, at + 46 + nameLength));
      at += 46 + nameLength + extra + comment;
      if (path.endsWith("/")) continue;
      if (local + 30 > bytes.length || view.getUint32(local, true) !== 0x04034b50) throw new Error("damaged zip file");
      const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
      const raw = bytes.subarray(start, start + packed);
      if (method === 0) files.push({ path, data: raw.slice() });
      else if (method === 8 && typeof DecompressionStream !== "undefined") files.push({ path, data: await inflate(raw) });
      else throw new Error("unsupported compression in " + path);
    }
    return files;
  }
  return { write, read, crc32 };
})();
if (typeof module !== "undefined") module.exports = CrankedZip;
