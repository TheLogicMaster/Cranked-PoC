// Browser front end: the engine (loading, the frame loop, audio). It runs on the page's own thread (the
// default) or in a worker (worker.js, with ?worker=1), with the same messages either way. Messages to it: load (a
// zip's bytes or a folder's files), input, screen (the screen's look), pause, resume, audioPort (a MessagePort to
// the page's AudioWorklet). Messages from it: ready, loaded, frame (RGBA, width by height), stopped.
"use strict";
function createCrankedEngine(postMessage, transfers) {

const RATE = 44100, STEP_MS = 1000 / 60;
let M = null, running = false, paused = false, timer = 0, last = 0, carry = 0;
let input = { buttons: 0, crank: 0, docked: true };
let audioPort = null, audioPtr = 0, frameMs = 0;
let frameFn, audioFn, failedFn, renderFn, renderWidthFn, renderHeightFn;
// the screen's look, as web_render takes it (flags: 1 blend frames, 2 pixel grid, 4 pixel shadow, 8 scanlines,
// 16 device frame)
let screenFx = { colors: 0, flags: 0, light: 0, tiltX: 0, tiltY: 0, scale: 1 };

createCranked({ printErr: t => console.warn(t), print: t => console.log(t) }).then(module => {
  M = module;
  frameFn = M.cwrap("web_frame", "number", ["number", "number", "number", "number"]);
  audioFn = M.cwrap("web_audio", null, ["number", "number"]);
  failedFn = M.cwrap("web_failed", "number", []);
  renderFn = M.cwrap("web_render", "number", ["number", "number", "number", "number", "number", "number"]);
  renderWidthFn = M.cwrap("web_render_width", "number", []);
  renderHeightFn = M.cwrap("web_render_height", "number", []);
  audioPtr = M._malloc(RATE * 4);
  try { M.FS.mkdir("/appData"); } catch (e) {}
  M.FS.mount(M.IDBFS, {}, "/appData");
  M.FS.syncfs(true, () => postMessage({ type: "ready" }));
  setInterval(() => { if (running) M.FS.syncfs(false, () => {}); }, 5000);
});

function rmTree(path) {
  try {
    for (const name of M.FS.readdir(path)) {
      if (name === "." || name === "..") continue;
      const full = path + "/" + name;
      if (M.FS.isDir(M.FS.stat(full).mode)) rmTree(full); else M.FS.unlink(full);
    }
    M.FS.rmdir(path);
  } catch (e) {}
}

function load(msg) {
  stop();
  let path;
  if (msg.kind === "zip") { M.FS.writeFile("/game.zip", msg.zip); path = "/game.zip"; }
  else {
    rmTree("/game.pdx"); M.FS.mkdir("/game.pdx");
    for (const f of msg.files) {
      const parts = f.path.split("/"); let dir = "/game.pdx";
      for (const p of parts.slice(0, -1)) { dir += "/" + p; try { M.FS.mkdir(dir); } catch (err) {} }
      M.FS.writeFile(dir + "/" + parts[parts.length - 1], f.data);
    }
    path = "/game.pdx";
  }
  const t0 = performance.now();
  const ok = M.ccall("web_load", "number", ["string"], [path]) === 1;
  const info = key => M.ccall("web_info", "string", ["string"], [key]);
  postMessage({ type: "loaded", ok, error: ok ? "" : M.ccall("web_error", "string", [], []), loadMs: performance.now() - t0,
                info: ok ? { name: info("name"), author: info("author"), bundleID: info("bundleID"), dataFolder: info("_dataFolder") } : null });
  if (ok) { running = true; paused = false; last = 0; carry = 0; frameMs = 0; schedule(0); }
}

// The frame as shown: the screen through its look (ScreenEffects)
function postFrame() {
  const fx = screenFx;
  const ptr = renderFn(fx.colors, fx.flags, fx.light, fx.tiltX, fx.tiltY, fx.scale);
  if (!ptr) return;
  const width = renderWidthFn(), height = renderHeightFn();
  const rgba = M.HEAPU8.slice(ptr, ptr + width * height * 4); // a copy, so it can be transferred
  postMessage({ type: "frame", rgba: rgba.buffer, width, height, frameMs }, transfers ? [rgba.buffer] : undefined);
}

function stop() { running = false; clearTimeout(timer); }
function schedule(delay) { clearTimeout(timer); timer = setTimeout(step, delay); }

function step() {
  if (!running || paused) return;
  const now = performance.now();
  const dt = last ? Math.min(now - last, 100) : STEP_MS; // a stall does not make the game jump
  last = now;
  const ptr = frameFn(input.buttons, input.crank, input.docked ? 1 : 0, Math.round(dt * 1000));
  const spent = performance.now() - now;
  frameMs = frameMs ? frameMs * 0.95 + spent * 0.05 : spent;
  if (ptr) postFrame();
  carry += RATE * dt / 1000; const frames = Math.min(Math.floor(carry), RATE); carry -= Math.floor(carry);
  if (frames > 0) {
    audioFn(audioPtr, frames);
    if (audioPort) {
      const chunk = M.HEAP16.slice(audioPtr >> 1, (audioPtr >> 1) + frames * 2);
      audioPort.postMessage(chunk, [chunk.buffer]);
    }
  }
  if (failedFn()) { stop(); postMessage({ type: "stopped", error: M.ccall("web_error", "string", [], []) }); return; }
  schedule(Math.max(0, STEP_MS - (performance.now() - now)));
}

return e => {
  const msg = e.data;
  if (msg.type === "load") { if (M) load(msg); }
  else if (msg.type === "input") input = msg.input;
  else if (msg.type === "screen") { screenFx = msg.screen; if (M && running && paused) postFrame(); } // drawn again while paused
  else if (msg.type === "pause") { paused = true; clearTimeout(timer); if (M) M.FS.syncfs(false, () => {}); }
  else if (msg.type === "resume") { if (running && paused) { paused = false; last = 0; schedule(0); } }
  else if (msg.type === "audioPort") audioPort = msg.port;
  else if (msg.type === "exportSaves") { if (M) exportSaves(msg.folder); }
  else if (msg.type === "importSaves") { if (M) importSaves(msg.folder, msg.files); }
};

// Save data: /appData/<data folder>/... (the folder is the game's bundle ID). A game's data is replaced only while
// the game is stopped; the page loads the game again afterwards.
function safeFolder(name) { return typeof name === "string" && /^[^/\\]+$/.test(name) && name !== "." && name !== ".."; }
function exportSaves(folder) {
  const files = [];
  const walk = (dir, rel) => {
    for (const name of M.FS.readdir(dir)) {
      if (name === "." || name === "..") continue;
      const full = dir + "/" + name, path = rel ? rel + "/" + name : name;
      if (M.FS.isDir(M.FS.stat(full).mode)) walk(full, path); else files.push({ path, data: M.FS.readFile(full) });
    }
  };
  try { if (safeFolder(folder)) walk("/appData/" + folder, ""); } catch (e) {}
  postMessage({ type: "saves", folder, files });
}
function importSaves(folder, files) {
  if (!safeFolder(folder)) { postMessage({ type: "imported", ok: false, error: "no data folder" }); return; }
  stop();
  M.ccall("web_unload", null, [], []);
  const root = "/appData/" + folder;
  rmTree(root);
  try { M.FS.mkdir(root); } catch (e) {}
  for (const f of files) {
    const parts = f.path.split("/").filter(p => p && p !== "." && p !== "..");
    if (!parts.length) continue;
    let dir = root;
    for (const p of parts.slice(0, -1)) { dir += "/" + p; try { M.FS.mkdir(dir); } catch (e) {} }
    M.FS.writeFile(dir + "/" + parts[parts.length - 1], f.data);
  }
  M.FS.syncfs(false, err => postMessage({ type: "imported", ok: !err, error: err ? String(err) : "" }));
}
}
