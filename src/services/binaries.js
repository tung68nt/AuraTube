// Cross-platform discovery (and on-demand download) of yt-dlp and a JavaScript runtime.
// Works on macOS, Windows and Linux, with or without Homebrew / Python / Node installed.
const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');

const IS_WIN = process.platform === 'win32';
const EXE = IS_WIN ? '.exe' : '';

const YTDLP_ASSET = {
  win32: 'yt-dlp.exe',
  darwin: 'yt-dlp_macos',
  linux: process.arch === 'arm64' ? 'yt-dlp_linux_aarch64' : 'yt-dlp_linux'
}[process.platform] || 'yt-dlp';

function dataDir() {
  let base;
  if (IS_WIN) base = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
  else if (process.platform === 'darwin') base = path.join(os.homedir(), 'Library', 'Application Support');
  else base = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
  return path.join(base, 'AuraTube', 'bin');
}

const MANAGED_YTDLP = path.join(dataDir(), `yt-dlp${EXE}`);

function isExecutable(p) {
  try {
    fs.accessSync(p, IS_WIN ? fs.constants.F_OK : fs.constants.X_OK);
    return fs.statSync(p).isFile() && fs.statSync(p).size > 100 * 1024;
  } catch (_) {
    return false;
  }
}

function findOnPath(name) {
  const exts = IS_WIN ? ['.exe', '.cmd', ''] : [''];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const p = path.join(dir, name + ext);
      try {
        if (fs.statSync(p).isFile()) return p;
      } catch (_) {}
    }
  }
  return null;
}

function bundledDir() {
  // Packaged Electron app: <resources>/bin ; dev checkout: <repo>/bin
  const dirs = [];
  if (process.resourcesPath) dirs.push(path.join(process.resourcesPath, 'bin'));
  dirs.push(path.join(__dirname, '..', '..', 'bin'));
  return dirs;
}

function findYtdlp() {
  const candidates = [
    MANAGED_YTDLP,
    ...bundledDir().map(d => path.join(d, `yt-dlp${EXE}`)),
    '/opt/homebrew/bin/yt-dlp',
    '/usr/local/bin/yt-dlp',
    '/usr/bin/yt-dlp'
  ];
  for (const c of candidates) if (isExecutable(c)) return c;
  return findOnPath('yt-dlp');
}

function download(url, dest, redirects = 0) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'AuraTube' } }, res => {
      if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && redirects < 10) {
        res.resume();
        return resolve(download(res.headers.location, dest, redirects + 1));
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`Tải yt-dlp thất bại (HTTP ${res.statusCode})`));
      }
      const out = fs.createWriteStream(dest);
      res.pipe(out);
      out.on('finish', () => out.close(resolve));
      out.on('error', reject);
    }).on('error', reject);
  });
}

let installPromise = null;

/** Download the standalone yt-dlp build for this OS into the app data dir. */
function installYtdlp() {
  if (installPromise) return installPromise;
  installPromise = (async () => {
    fs.mkdirSync(path.dirname(MANAGED_YTDLP), { recursive: true });
    const tmp = `${MANAGED_YTDLP}.download`;
    let lastErr;
    for (let i = 0; i < 3; i++) {
      try {
        await download(`https://github.com/yt-dlp/yt-dlp/releases/latest/download/${YTDLP_ASSET}`, tmp);
        if (fs.statSync(tmp).size < 100 * 1024) throw new Error('File yt-dlp tải về không hợp lệ');
        if (!IS_WIN) fs.chmodSync(tmp, 0o755);
        try { fs.unlinkSync(MANAGED_YTDLP); } catch (_) {}
        fs.renameSync(tmp, MANAGED_YTDLP);
        return MANAGED_YTDLP;
      } catch (e) {
        lastErr = e;
        await new Promise(r => setTimeout(r, 1500 * (i + 1)));
      }
    }
    const existing = findYtdlp();
    if (existing) return existing;
    throw lastErr || new Error('Không thể tải yt-dlp');
  })().finally(() => { installPromise = null; });
  return installPromise;
}

async function ensureYtdlp() {
  const managedAge = (() => {
    try { return Date.now() - fs.statSync(MANAGED_YTDLP).mtimeMs; } catch (_) { return null; }
  })();
  const found = findYtdlp();
  if (!found) return installYtdlp();
  // Keep the app-managed copy fresh (YouTube changes often break old yt-dlp).
  if (found === MANAGED_YTDLP && managedAge > 3 * 24 * 3600 * 1000) {
    installYtdlp().catch(() => {});
  }
  return found;
}

/**
 * yt-dlp needs a JS runtime for YouTube, otherwise it fails with
 * "Requested format is not available". Prefer deno/node on the system,
 * fall back to Electron's own bundled Node (ELECTRON_RUN_AS_NODE=1).
 */
function jsRuntime() {
  const deno = ['/opt/homebrew/bin/deno', '/usr/local/bin/deno', path.join(os.homedir(), '.deno', 'bin', `deno${EXE}`)]
    .find(p => fs.existsSync(p)) || findOnPath('deno');
  if (deno) return { args: ['--js-runtimes', `deno:${deno}`], env: {} };

  if (!process.versions.electron) {
    return { args: ['--js-runtimes', `node:${process.execPath}`], env: {} };
  }
  const node = ['/opt/homebrew/bin/node', '/usr/local/bin/node', '/usr/bin/node'].find(p => fs.existsSync(p))
    || findOnPath('node');
  if (node) return { args: ['--js-runtimes', `node:${node}`], env: {} };
  return { args: ['--js-runtimes', `node:${process.execPath}`], env: { ELECTRON_RUN_AS_NODE: '1' } };
}

function ffmpegLocation() {
  for (const d of bundledDir()) {
    if (fs.existsSync(path.join(d, `ffmpeg${EXE}`))) return d;
  }
  const p = ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg', '/usr/bin/ffmpeg'].find(x => fs.existsSync(x))
    || findOnPath('ffmpeg');
  return p ? path.dirname(p) : null;
}

module.exports = { findYtdlp, ensureYtdlp, installYtdlp, jsRuntime, ffmpegLocation, MANAGED_YTDLP };
