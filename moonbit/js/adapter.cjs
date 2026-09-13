"use strict";
// Minimal Node platform adapter for the MoonBit JS backend.
//
// Boundary: filesystem, realpath/containment, SHA-256, YAML loading and PNG
// decoding/encoding live here. All schema, cross-file semantic and pixel
// comparison logic lives in MoonBit (src/core). Nothing in this file calls
// Python or performs contract judgement beyond parsing/IO.

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const zlib = require("zlib");

// ---------------------------------------------------------------- YAML subset
// Parses the block-style YAML used by this kit (mappings, sequences, quoted and
// plain scalars) into a JavaScript value, detecting duplicate mapping keys.
function stripComment(line) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === "'" && !inDouble) inSingle = !inSingle;
    else if (ch === '"' && !inSingle) inDouble = !inDouble;
    else if (ch === "#" && !inSingle && !inDouble && (i === 0 || line[i - 1] === "\t" || line[i - 1] === " ")) {
      return line.slice(0, i);
    }
  }
  return line;
}

function yamlLines(text) {
  const raw = text.split(/\r\n|\r|\n/);
  const out = [];
  for (const line of raw) {
    const stripped = stripComment(line).replace(/\s+$/, "");
    if (stripped.trim() === "") continue;
    let indent = 0;
    while (indent < stripped.length && stripped[indent] === " ") indent++;
    out.push({ indent, text: stripped.slice(indent) });
  }
  return out;
}

function parseScalar(s) {
  const t = s.trim();
  if (t === "") return null;
  if (t === "null" || t === "~") return null;
  if (t === "true") return true;
  if (t === "false") return false;
  if (t.startsWith("'") && t.endsWith("'") && t.length >= 2) {
    return t.slice(1, -1).replace(/''/g, "'");
  }
  if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
    try {
      return JSON.parse(t);
    } catch (_) {
      return t.slice(1, -1);
    }
  }
  if (/^-?\d+$/.test(t)) {
    const n = Number(t);
    if (Number.isSafeInteger(n)) return n;
  }
  if (/^-?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?$/.test(t) && /[.eE]/.test(t)) {
    return Number(t);
  }
  return t;
}

function splitMapEntry(text) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === "'" && !inDouble) inSingle = !inSingle;
    else if (ch === '"' && !inSingle) inDouble = !inDouble;
    else if (ch === ":" && !inSingle && !inDouble) {
      const next = text[i + 1];
      if (next === undefined || next === " " || next === "\t") {
        return [text.slice(0, i), text.slice(i + 1)];
      }
    }
  }
  return null;
}

function parseKey(k) {
  const v = parseScalar(k);
  if (v === null) return "null";
  return typeof v === "string" ? v : String(v);
}

function setKey(obj, key, value) {
  if (Object.prototype.hasOwnProperty.call(obj, key)) {
    throw new Error("Duplicate YAML key: " + key);
  }
  obj[key] = value;
}

function parseYaml(text) {
  const lines = yamlLines(text);
  const res = parseNode(lines, 0, 0);
  return res[0];
}

function nextIndent(lines, i, parentIndent) {
  if (i >= lines.length) return null;
  const ind = lines[i].indent;
  if (ind > parentIndent) return ind;
  if (ind === parentIndent && lines[i].text.startsWith("-")) return ind;
  return null;
}

function parseNode(lines, i, indent) {
  if (i >= lines.length || lines[i].indent < indent) return [null, i];
  if (lines[i].text === "-" || lines[i].text.startsWith("- ")) {
    return parseSeq(lines, i, indent);
  }
  return parseMap(lines, i, indent);
}

function parseSeq(lines, i, indent) {
  const out = [];
  while (i < lines.length && lines[i].indent === indent && (lines[i].text === "-" || lines[i].text.startsWith("- "))) {
    const rest = lines[i].text === "-" ? "" : lines[i].text.slice(2);
    if (rest === "") {
      const [v, ni] = parseNode(lines, i + 1, lines[i + 1] ? lines[i + 1].indent : indent + 2);
      out.push(v);
      i = ni;
    } else {
      const entry = splitMapEntry(rest);
      if (entry) {
        const obj = {};
        const key = parseKey(entry[0]);
        if (entry[1].trim() === "") {
          const ni0 = nextIndent(lines, i + 1, indent);
          if (ni0 !== null) {
            const [v, ni] = parseNode(lines, i + 1, ni0);
            setKey(obj, key, v);
            i = ni;
          } else {
            setKey(obj, key, null);
            i = i + 1;
          }
        } else {
          setKey(obj, key, parseScalar(entry[1]));
          i = i + 1;
        }
        while (i < lines.length && lines[i].indent > indent && !(lines[i].text === "-" || lines[i].text.startsWith("- "))) {
          const cont = splitMapEntry(lines[i].text);
          if (!cont) break;
          const ckey = parseKey(cont[0]);
          if (cont[1].trim() === "") {
            const ni1 = nextIndent(lines, i + 1, lines[i].indent);
            if (ni1 !== null) {
              const [v, ni] = parseNode(lines, i + 1, ni1);
              setKey(obj, ckey, v);
              i = ni;
            } else {
              setKey(obj, ckey, null);
              i = i + 1;
            }
          } else {
            setKey(obj, ckey, parseScalar(cont[1]));
            i = i + 1;
          }
        }
        out.push(obj);
      } else {
        out.push(parseScalar(rest));
        i = i + 1;
      }
    }
  }
  return [out, i];
}

function parseMap(lines, i, indent) {
  const obj = {};
  while (i < lines.length && lines[i].indent === indent && !(lines[i].text === "-" || lines[i].text.startsWith("- "))) {
    const entry = splitMapEntry(lines[i].text);
    if (!entry) {
      throw new Error("Invalid YAML mapping line: " + lines[i].text);
    }
    const key = parseKey(entry[0]);
    if (entry[1].trim() === "") {
      const ni0 = nextIndent(lines, i + 1, indent);
      if (ni0 !== null) {
        const [v, ni] = parseNode(lines, i + 1, ni0);
        setKey(obj, key, v);
        i = ni;
      } else {
        setKey(obj, key, null);
        i = i + 1;
      }
    } else {
      setKey(obj, key, parseScalar(entry[1]));
      i = i + 1;
    }
  }
  return [obj, i];
}

function yamlToJson(text) {
  const value = parseYaml(text);
  return JSON.stringify(value);
}

// ------------------------------------------------------------------ PNG codec
let CRC_TABLE = null;
function crcTable() {
  if (CRC_TABLE) return CRC_TABLE;
  CRC_TABLE = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    CRC_TABLE[n] = c;
  }
  return CRC_TABLE;
}

function crc32(buf) {
  const table = crcTable();
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = table[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

const PNG_SIG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

function unfilter(raw, width, height, bpp) {
  const stride = width * bpp;
  const out = Buffer.alloc(height * stride);
  let pos = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[pos++];
    const row = raw.subarray(pos, pos + stride);
    pos += stride;
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? cur[x - bpp] : 0;
      const b = prev ? prev[x] : 0;
      const c = prev && x >= bpp ? prev[x - bpp] : 0;
      let v = row[x];
      if (filter === 1) v = (v + a) & 0xff;
      else if (filter === 2) v = (v + b) & 0xff;
      else if (filter === 3) v = (v + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) v = (v + paeth(a, b, c)) & 0xff;
      cur[x] = v;
    }
  }
  return out;
}

function channelsForColorType(colorType) {
  switch (colorType) {
    case 0:
      return 1;
    case 2:
      return 3;
    case 3:
      return 1;
    case 4:
      return 2;
    case 6:
      return 4;
    default:
      return 0;
  }
}

function decodePngBuffer(buf) {
  if (buf.length < 8 || !buf.subarray(0, 8).equals(PNG_SIG)) return null;
  let pos = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let interlace = 0;
  let palette = null;
  let trns = null;
  const idat = [];
  while (pos + 8 <= buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    pos += 12 + len;
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      interlace = data[12];
    } else if (type === "PLTE") {
      palette = Buffer.from(data);
    } else if (type === "tRNS") {
      trns = Buffer.from(data);
    } else if (type === "IDAT") {
      idat.push(Buffer.from(data));
    } else if (type === "IEND") {
      break;
    }
  }
  if (interlace !== 0 || (bitDepth !== 8 && bitDepth !== 16)) return null;
  const srcChannels = channelsForColorType(colorType);
  if (srcChannels === 0) return null;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const bytesPerSample = bitDepth / 8;
  const bpp = srcChannels * bytesPerSample;
  const unfiltered = unfilter(raw, width, height, bpp);
  let samples = unfiltered;
  if (bitDepth === 16) {
    samples = Buffer.alloc(width * height * srcChannels);
    for (let i = 0; i < samples.length; i++) samples[i] = unfiltered[i * 2];
  }
  let outChannels;
  let pixels;
  if (colorType === 3) {
    outChannels = 4;
    pixels = Buffer.alloc(width * height * 4);
    for (let i = 0; i < width * height; i++) {
      const idx = samples[i];
      pixels[i * 4] = palette[idx * 3];
      pixels[i * 4 + 1] = palette[idx * 3 + 1];
      pixels[i * 4 + 2] = palette[idx * 3 + 2];
      pixels[i * 4 + 3] = trns && idx < trns.length ? trns[idx] : 255;
    }
  } else {
    outChannels = srcChannels;
    pixels = Buffer.from(samples);
  }
  return { width, height, channels: outChannels, pixels };
}

function packDecoded(dec) {
  const header = Buffer.alloc(16);
  header.writeUInt32BE(dec.width, 0);
  header.writeUInt32BE(dec.height, 4);
  header.writeUInt32BE(dec.channels, 8);
  header.writeUInt32BE(0, 12);
  return new Uint8Array(Buffer.concat([header, dec.pixels]));
}

function encodePngBuffer(width, height, channels, data) {
  const colorType = channels === 4 ? 6 : channels === 3 ? 2 : channels === 2 ? 4 : 0;
  const stride = width * channels;
  const raw = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0;
    Buffer.from(data).copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const compressed = zlib.deflateSync(raw);
  function chunk(type, payload) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(payload.length, 0);
    const typeBuf = Buffer.from(type, "ascii");
    const body = Buffer.concat([typeBuf, payload]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body), 0);
    return Buffer.concat([len, body, crc]);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = colorType;
  return Buffer.concat([PNG_SIG, chunk("IHDR", ihdr), chunk("IDAT", compressed), chunk("IEND", Buffer.alloc(0))]);
}

// ------------------------------------------------------------------- registry
globalThis.__astrafact = {
  readText(p) {
    try {
      return fs.readFileSync(p, "utf8");
    } catch (_) {
      return undefined;
    }
  },
  readBytes(p) {
    try {
      return new Uint8Array(fs.readFileSync(p));
    } catch (_) {
      return undefined;
    }
  },
  sha256Hex(bytes) {
    return crypto.createHash("sha256").update(Buffer.from(bytes)).digest("hex");
  },
  isFile(p) {
    try {
      return fs.statSync(p).isFile();
    } catch (_) {
      return false;
    }
  },
  realpath(p) {
    try {
      return fs.realpathSync(p);
    } catch (_) {
      return path.resolve(p);
    }
  },
  isWithin(child, root) {
    const rel = path.relative(root, child);
    return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
  },
  join(a, b) {
    return path.join(a, b);
  },
  parseYaml(text) {
    try {
      return yamlToJson(text);
    } catch (_) {
      return undefined;
    }
  },
  writeText(p, text) {
    try {
      fs.writeFileSync(p, text, "utf8");
      return true;
    } catch (_) {
      return false;
    }
  },
  tmpdir() {
    return require("os").tmpdir();
  },
  mkdir(p) {
    try {
      fs.mkdirSync(p, { recursive: true });
      return true;
    } catch (_) {
      return false;
    }
  },
  symlink(target, link) {
    try {
      fs.symlinkSync(target, link);
      return true;
    } catch (_) {
      return false;
    }
  },
  decodePng(p) {
    try {
      const dec = decodePngBuffer(fs.readFileSync(p));
      return dec ? packDecoded(dec) : undefined;
    } catch (_) {
      return undefined;
    }
  },
  encodePng(p, width, height, channels, data) {
    try {
      fs.writeFileSync(p, encodePngBuffer(width, height, channels, Buffer.from(data)));
      return true;
    } catch (_) {
      return false;
    }
  },
  getArgs() {
    if (typeof process !== "undefined" && process.argv) return process.argv.slice();
    return [];
  },
  cwd() {
    return process.cwd();
  },
  printStdout(s) {
    process.stdout.write(s);
  },
  printStderr(s) {
    process.stderr.write(s);
  },
  exit(code) {
    process.exit(code);
  },
};
