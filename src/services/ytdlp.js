const { spawn, execFile } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

// Path to yt-dlp binary (detected on macOS via homebrew or system)
const YTDLP_PATH = fs.existsSync('/opt/homebrew/bin/yt-dlp')
  ? '/opt/homebrew/bin/yt-dlp'
  : (fs.existsSync('/usr/local/bin/yt-dlp') ? '/usr/local/bin/yt-dlp' : 'yt-dlp');

// Find actual system Node.js binary (CRITICAL: NEVER use process.execPath inside Electron!)
function getRealNodePath() {
  const candidates = [
    '/opt/homebrew/bin/node',
    '/usr/local/bin/node',
    '/usr/bin/node'
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return 'node';
}

const NODE_PATH = getRealNodePath();

const DOWNLOADS_DIR = path.join(os.homedir(), 'Downloads', 'YouTube_Adfree');
if (!fs.existsSync(DOWNLOADS_DIR)) {
  fs.mkdirSync(DOWNLOADS_DIR, { recursive: true });
}

const INFO_YTDLP_ARGS = [
  '--no-warnings',
  '--no-update',
  '--force-ipv4',
  '--js-runtimes', `node:${NODE_PATH}`
];

const COMMON_YTDLP_ARGS = [
  '--no-warnings',
  '--no-update',
  '--force-ipv4',
  '--js-runtimes', `node:${NODE_PATH}`
];

const infoCache = new Map();
const inFlightInfoPromises = new Map();

/**
 * Get detailed video info using yt-dlp -j (discovers all resolutions)
 */
async function getVideoInfo(videoId) {
  if (!/^[a-zA-Z0-9_-]{11}$/.test(videoId)) {
    throw new Error('Invalid YouTube video ID format');
  }
  const cached = infoCache.get(videoId);
  if (cached && (Date.now() - cached.time < 30 * 60 * 1000)) {
    return cached.data;
  }
  if (inFlightInfoPromises.has(videoId)) {
    return inFlightInfoPromises.get(videoId);
  }

  const promise = new Promise((resolve, reject) => {
    const url = `https://www.youtube.com/watch?v=${videoId}`;
    const args = [
      ...INFO_YTDLP_ARGS,
      '--dump-json',
      '--no-playlist',
      '--',
      url
    ];

    execFile(YTDLP_PATH, args, { maxBuffer: 20 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        return reject(new Error(stderr || error.message));
      }
      try {
        const info = JSON.parse(stdout);
        // Filter and format available streams
        const formats = (info.formats || []).filter(f => f.url).map(f => ({
          format_id: f.format_id,
          ext: f.ext,
          resolution: f.resolution || (f.height ? `${f.height}p` : 'audio only'),
          height: f.height,
          filesize: f.filesize || f.filesize_approx,
          vcodec: f.vcodec,
          acodec: f.acodec,
          has_video: f.vcodec && f.vcodec !== 'none',
          has_audio: f.acodec && f.acodec !== 'none',
          url: f.url
        }));

        // Extract available unique video heights (e.g. [2160, 1440, 1080, 720, 480, 360])
        const availableResolutions = [...new Set(
          (info.formats || [])
            .map(f => f.height)
            .filter(h => typeof h === 'number' && h >= 144)
        )].sort((a, b) => b - a);

        const data = {
          id: info.id,
          title: info.title,
          description: info.description,
          thumbnail: info.thumbnail,
          uploader: info.uploader || info.channel,
          uploaderUrl: info.uploader_url,
          uploaderAvatar: info.channel_follower_count ? null : null,
          duration: info.duration,
          viewCount: info.view_count,
          likeCount: info.like_count,
          uploadDate: info.upload_date,
          formats: formats,
          availableResolutions: availableResolutions
        };
        infoCache.set(videoId, { time: Date.now(), data });
        resolve(data);
      } catch (err) {
        reject(new Error(`Failed to parse yt-dlp output: ${err.message}`));
      }
    });
  });

  inFlightInfoPromises.set(videoId, promise);
  try {
    return await promise;
  } finally {
    inFlightInfoPromises.delete(videoId);
  }
}

// In-memory stream URL cache for instantaneous quality switching (TTL: 2 hours)
const streamUrlCache = new Map();
const inFlightStreamPromises = new Map();

/**
 * Get direct playable media URL with video + audio combined or best separate streams
 */
async function getBestStreamUrl(videoId, quality = '1080', forceRefresh = false) {
  if (!/^[a-zA-Z0-9_-]{11}$/.test(videoId)) {
    throw new Error('Invalid YouTube video ID format');
  }
  const cacheKey = `${videoId}_${quality}`;
  if (!forceRefresh) {
    const cached = streamUrlCache.get(cacheKey);
    if (cached && (Date.now() - cached.time < 2 * 3600 * 1000)) {
      return cached.data;
    }
  } else {
    streamUrlCache.delete(cacheKey);
  }

  if (inFlightStreamPromises.has(cacheKey)) {
    return inFlightStreamPromises.get(cacheKey);
  }

  const promise = new Promise((resolve, reject) => {
    const url = `https://www.youtube.com/watch?v=${videoId}`;
    
    let formatFilter = '18/best[height<=360][ext=mp4]/best';
    let isSeparate = false;
    let runArgs = COMMON_YTDLP_ARGS;

    if (quality === 'audio') {
      formatFilter = 'bestaudio[protocol=https]/140[protocol=https]/bestaudio/18/best';
      runArgs = INFO_YTDLP_ARGS;
      isSeparate = false;
    } else if (quality === 'mini') {
      // mini-player: Lightweight 360p video stream for menubar popover
      formatFilter = '18/bestvideo[height<=360][protocol=https]+bestaudio[protocol=https]/bestvideo[height<=360]+bestaudio/best[height<=360]/best';
      runArgs = INFO_YTDLP_ARGS;
      isSeparate = true;
    } else {
      // Full authentic quality (2160p 4K, 1440p 2K, 1080p, 720p, 480p, 360p, 240p, 144p):
      // Extracts pure direct Google Video bitstream with zero compression
      const targetHeight = parseInt(quality, 10) || 1080;
      formatFilter = `bestvideo[height<=${targetHeight}][protocol=https]+bestaudio[protocol=https]/bestvideo[height<=${targetHeight}]+bestaudio/18/best`;
      runArgs = INFO_YTDLP_ARGS;
      isSeparate = true;
    }

    const args = [
      ...runArgs,
      '-f', formatFilter,
      '-g',
      '--no-playlist',
      '--',
      url
    ];

    execFile(YTDLP_PATH, args, (error, stdout, stderr) => {
      if (error) {
        // Fallback to 360p/best if high-res fails
        return execFile(YTDLP_PATH, [
          ...COMMON_YTDLP_ARGS,
          '-f', '18/bestvideo[height<=360]+bestaudio/best',
          '-g',
          '--no-playlist',
          '--',
          url
        ], (fallbackErr, fallbackStdout) => {
          if (fallbackErr) return reject(new Error(stderr || error.message));
          const fallbackUrls = (fallbackStdout || '').trim().split('\n').filter(u => u.startsWith('http'));
          if (fallbackUrls.length > 0) {
            const data = { videoUrl: fallbackUrls[0], audioUrl: fallbackUrls[1] || null, hasSeparateAudio: fallbackUrls.length > 1 };
            streamUrlCache.set(cacheKey, { time: Date.now(), data });
            resolve(data);
          } else {
            reject(new Error('No stream URL found'));
          }
        });
      }

      const urls = stdout.trim().split('\n').filter(u => u.startsWith('http'));
      if (urls.length >= 2 && isSeparate) {
        const streamData = {
          videoUrl: urls[0],
          audioUrl: urls[1],
          hasSeparateAudio: true
        };
        streamUrlCache.set(cacheKey, { time: Date.now(), data: streamData });
        resolve(streamData);
      } else if (urls.length >= 1) {
        const streamData = {
          videoUrl: (quality === 'audio' ? null : urls[0]),
          audioUrl: (quality === 'audio' ? urls[0] : null),
          hasSeparateAudio: false
        };
        streamUrlCache.set(cacheKey, { time: Date.now(), data: streamData });
        resolve(streamData);
      } else {
        reject(new Error('No stream URL found'));
      }
    });
  });

  inFlightStreamPromises.set(cacheKey, promise);
  try {
    return await promise;
  } finally {
    inFlightStreamPromises.delete(cacheKey);
  }
}

function invalidateStreamCache(videoId, quality) {
  if (quality) {
    streamUrlCache.delete(`${videoId}_${quality}`);
  } else {
    for (const key of streamUrlCache.keys()) {
      if (key.startsWith(`${videoId}_`)) {
        streamUrlCache.delete(key);
      }
    }
  }
}

/**
 * Search videos via yt-dlp (ytsearch)
 */
async function searchVideos(query, limit = 20) {
  return new Promise((resolve, reject) => {
    const args = [
      `ytsearch${limit}:${query}`,
      '--dump-json',
      '--default-search', 'ytsearch',
      '--flat-playlist',
      '--no-warnings'
    ];

    execFile(YTDLP_PATH, args, { maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        return reject(new Error(stderr || error.message));
      }
      try {
        const lines = stdout.trim().split('\n').filter(Boolean);
        const results = lines.map(line => {
          try {
            const item = JSON.parse(line);
            // Ignore channel or playlist entries that do not have video IDs
            if (!item.id || item.id.startsWith('UC') || item.id.length !== 11) {
              return null;
            }
            return {
              id: item.id,
              title: item.title,
              uploader: item.uploader || item.channel,
              duration: item.duration,
              viewCount: item.view_count,
              thumbnail: item.thumbnails ? item.thumbnails[0]?.url : `https://i.ytimg.com/vi/${item.id}/hqdefault.jpg`,
              url: `https://www.youtube.com/watch?v=${item.id}`
            };
          } catch (e) {
            return null;
          }
        }).filter(Boolean);
        resolve(results);
      } catch (err) {
        reject(new Error(`Failed to parse search results: ${err.message}`));
      }
    });
  });
}

/**
 * Start downloading a video or audio to local directory
 */
function downloadMedia(videoId, format = 'mp4', onProgress, onComplete, onError) {
  if (!/^[a-zA-Z0-9_-]{11}$/.test(videoId)) {
    if (onError) onError(new Error('Invalid YouTube video ID format'));
    return null;
  }
  const url = `https://www.youtube.com/watch?v=${videoId}`;
  let args = [];
  const filenameTemplate = path.join(DOWNLOADS_DIR, '%(title)s.%(ext)s');

  if (format === 'mp3') {
    args = [
      ...COMMON_YTDLP_ARGS,
      '-x',
      '--audio-format', 'mp3',
      '--audio-quality', '0',
      '-o', filenameTemplate,
      '--no-playlist',
      '--',
      url
    ];
  } else {
    const targetHeight = parseInt(format, 10);
    const formatFilter = !isNaN(targetHeight) && targetHeight > 0
      ? `bestvideo[height<=${targetHeight}][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=${targetHeight}]+bestaudio/best[height<=${targetHeight}]/best`
      : 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best';

    args = [
      ...COMMON_YTDLP_ARGS,
      '-f', formatFilter,
      '--merge-output-format', 'mp4',
      '-o', filenameTemplate,
      '--no-playlist',
      '--',
      url
    ];
  }

  const child = spawn(YTDLP_PATH, args);

  child.stdout.on('data', (data) => {
    const text = data.toString();
    // Parse progress e.g., "[download]  45.2% of 50.00MiB at 4.50MiB/s ETA 00:06"
    const match = text.match(/\[download\]\s+([\d\.]+)%/);
    if (match && onProgress) {
      onProgress(parseFloat(match[1]));
    }
  });

  child.stderr.on('data', (data) => {
    console.error(`Download stderr: ${data}`);
  });

  child.on('close', (code) => {
    if (code === 0) {
      if (onComplete) onComplete({ dir: DOWNLOADS_DIR });
    } else {
      if (onError) onError(new Error(`yt-dlp exited with code ${code}`));
    }
  });

  return child;
}

module.exports = {
  YTDLP_PATH,
  DOWNLOADS_DIR,
  COMMON_YTDLP_ARGS,
  getVideoInfo,
  getBestStreamUrl,
  invalidateStreamCache,
  searchVideos,
  downloadMedia
};
