const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { Readable } = require('stream');
const https = require('https');
const http = require('http');
const ytdlp = require('./src/services/ytdlp');
const invidious = require('./src/services/invidious');
const fastyoutube = require('./src/services/fastyoutube');

// Ensure Homebrew binaries are accessible even when launched from macOS Finder / /Applications
const defaultPaths = ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin'];
for (const p of defaultPaths) {
  if (!process.env.PATH || !process.env.PATH.includes(p)) {
    process.env.PATH = `${p}:${process.env.PATH || ''}`;
  }
}

const dns = require('node:dns');
try {
  dns.setDefaultResultOrder('ipv4first');
} catch (e) {}

// Global safety catch for stream and network aborts
process.on('uncaughtException', (err) => {
  if (err && (err.name === 'AbortError' || err.code === 'ABORT_ERR')) return;
  console.error('Unhandled server exception:', err);
});
process.on('unhandledRejection', (reason) => {
  if (reason && (reason.name === 'AbortError' || reason.code === 'ABORT_ERR')) return;
  console.error('Unhandled server rejection:', reason);
});

const app = express();
const PORT = process.env.PORT || 3000;

// Security Headers Middleware
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  next();
});

app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(express.static(path.join(__dirname, 'public'), {
  etag: false,
  maxAge: 0,
  setHeaders: (res) => {
    res.set('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.set('Pragma', 'no-cache');
    res.set('Expires', '0');
  }
}));

// Strict Input Validation Helpers
const VIDEO_ID_REGEX = /^[a-zA-Z0-9_-]{11}$/;
const VALID_QUALITIES = new Set(['2160', '1440', '1080', '720', '480', '360', '240', '144', 'audio', 'mini']);
const VALID_FORMATS = new Set(['mp4', 'mp3', '2160', '1440', '1080', '720', '480', '360']);

function isValidVideoId(id) {
  return typeof id === 'string' && VIDEO_ID_REGEX.test(id);
}

function sanitizeQuality(q) {
  if (typeof q === 'string' && VALID_QUALITIES.has(q)) return q;
  return '720';
}

function sanitizeFormat(f) {
  if (typeof f === 'string' && VALID_FORMATS.has(f)) return f;
  return 'mp4';
}

// Active downloads tracking
const activeDownloads = new Map();

// In-memory search cache (TTL: 30 minutes)
const searchCache = new Map();

const COOKIE_FILE = path.join(__dirname, '.user_cookie.txt');
function getSavedCookie() {
  if (fs.existsSync(COOKIE_FILE)) {
    return fs.readFileSync(COOKIE_FILE, 'utf8').trim();
  }
  return null;
}

/**
 * GET /api/account/status
 */
app.get('/api/account/status', (req, res) => {
  const cookie = getSavedCookie();
  res.json({ success: true, loggedIn: Boolean(cookie && cookie.length > 20) });
});

/**
 * POST /api/account/cookie
 * Save Google/YouTube Cookie
 */
app.post('/api/account/cookie', (req, res) => {
  const { cookie } = req.body;
  if (!cookie) {
    if (fs.existsSync(COOKIE_FILE)) fs.unlinkSync(COOKIE_FILE);
    return res.json({ success: true, loggedIn: false });
  }
  fs.writeFileSync(COOKIE_FILE, cookie, 'utf8');
  res.json({ success: true, loggedIn: true });
});

/**
 * GET /api/subscriptions
 * Fetch user's subscribed channels feed
 */
app.get('/api/subscriptions', async (req, res) => {
  try {
    const cookie = getSavedCookie();
    if (!cookie) {
      return res.json({ success: true, loggedIn: false, videos: [] });
    }
    const videos = await fastyoutube.getSubscriptions(cookie);
    res.json({ success: true, loggedIn: true, videos });
  } catch (err) {
    console.error('Subscriptions error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/account/open-desktop
 * Launch native app
 */
app.post('/api/account/open-desktop', (req, res) => {
  const { execFile } = require('child_process');
  execFile('/usr/bin/open', ['/Applications/AuraTube.app'], (err) => {
    if (err) console.warn('Failed to open native AuraTube.app:', err.message);
  });
  res.json({ success: true });
});

/**
 * GET /api/trending
 * Sub-second trending or personalized home feed
 */
app.get('/api/trending', async (req, res) => {
  try {
    const cookie = getSavedCookie();
    let videos = await fastyoutube.getTrendingVideos(cookie);
    if (!videos || videos.length === 0) {
      videos = await fastyoutube.searchYouTube('nhạc việt remix hot trend');
    }
    res.json({ success: true, videos, personalized: Boolean(cookie) });

    // Background pre-warm top 2 trending stream URLs so clicking is sub-millisecond
    if (videos && videos.length > 0) {
      setTimeout(() => {
        for (let i = 0; i < Math.min(2, videos.length); i++) {
          if (videos[i] && videos[i].id) {
            ytdlp.getBestStreamUrl(videos[i].id, '720').catch(() => {});
          }
        }
      }, 800);
    }
  } catch (error) {
    console.error('Trending error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * GET /api/shorts
 * Trending YouTube Shorts feed (< 60s, vertical short format)
 */
app.get('/api/shorts', async (req, res) => {
  try {
    let result = await fastyoutube.searchYouTube('#shorts việt nam');
    let videoList = (result && result.videos) || [];
    if (videoList.length === 0) {
      result = await fastyoutube.searchYouTube('#shorts trending');
      videoList = (result && result.videos) || [];
    }
    const shorts = videoList.filter(v => {
      if (!v.duration) return true;
      if (typeof v.duration === 'number') return v.duration <= 65;
      const str = String(v.duration).trim();
      const parts = str.split(':').map(Number);
      if (parts.length === 2) {
        const secs = parts[0] * 60 + parts[1];
        return secs <= 65; // Authentic YouTube Shorts duration <= 65s
      }
      if (parts.length === 1 && !isNaN(parts[0])) {
        return parts[0] <= 65;
      }
      return false;
    });
    res.json({ success: true, videos: shorts.length > 0 ? shorts : videoList });
  } catch (error) {
    console.error('Shorts error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * GET /api/search?q=...
 * Sub-second YouTube search
 */
app.get('/api/search', async (req, res) => {
  const query = (req.query.q || '').trim();
  if (!query) {
    return res.status(400).json({ success: false, error: 'Query parameter "q" is required' });
  }

  const cacheKey = query.toLowerCase();
  const cached = searchCache.get(cacheKey);
  if (cached && (Date.now() - cached.time < 30 * 60 * 1000)) {
    return res.json(cached.data);
  }

  try {
    const result = await fastyoutube.searchYouTube(query);
    const responseData = {
      success: true,
      channel: result.channel || null,
      videos: result.videos || []
    };
    if (responseData.videos.length > 0) {
      searchCache.set(cacheKey, { time: Date.now(), data: responseData });
      setTimeout(() => {
        for (let i = 0; i < Math.min(2, responseData.videos.length); i++) {
          if (responseData.videos[i] && responseData.videos[i].id) {
            ytdlp.getBestStreamUrl(responseData.videos[i].id, '720').catch(() => {});
          }
        }
      }, 500);
    }
    res.json(responseData);
  } catch (error) {
    console.error('Search error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * GET /api/info?v=...
 * Video metadata & available streams
 */
app.get('/api/info', async (req, res) => {
  const videoId = req.query.v;
  if (!isValidVideoId(videoId)) {
    return res.status(400).json({ success: false, error: 'Valid 11-character YouTube video ID "v" is required' });
  }

  try {
    const [info, sponsorSegments] = await Promise.all([
      ytdlp.getVideoInfo(videoId),
      invidious.getSponsorSegments(videoId)
    ]);
    res.json({
      success: true,
      info,
      sponsorSegments
    });
  } catch (error) {
    console.error('Video info error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * GET /api/stream?v=...&quality=720
 * Get direct playable stream URL
 */
app.get('/api/stream', async (req, res) => {
  const videoId = req.query.v;
  if (!isValidVideoId(videoId)) {
    return res.status(400).json({ success: false, error: 'Valid 11-character YouTube video ID "v" is required' });
  }
  const quality = sanitizeQuality(req.query.quality);

  try {
    const streams = await ytdlp.getBestStreamUrl(videoId, quality);
    res.json({
      success: true,
      ...streams,
      isAudioOnly: quality === 'audio',
      proxyVideoUrl: quality === 'audio' ? null : `/api/proxy-stream?v=${videoId}&quality=${quality}&type=video`,
      proxyAudioUrl: quality === 'audio'
        ? `/api/proxy-stream?v=${videoId}&quality=audio&type=audio`
        : (streams.hasSeparateAudio ? `/api/proxy-stream?v=${videoId}&quality=${quality}&type=audio` : null)
    });
  } catch (error) {
    console.error('Stream extraction error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * GET /api/proxy-stream?v=...&quality=720
 * High performance video stream proxy with full HTTP 206 Partial Content (Range) support.
 * Bypasses all browser referrer restrictions and CORS limits.
 */
app.get('/api/proxy-stream', async (req, res) => {
  const videoId = req.query.v;
  if (!isValidVideoId(videoId)) {
    return res.status(400).send('Invalid video ID');
  }
  const quality = sanitizeQuality(req.query.quality);
  const type = req.query.type === 'audio' ? 'audio' : 'video';

  function forwardStream(targetUrl, isRetry = false) {
    try {
      const parsed = new URL(targetUrl);
      const reqModule = parsed.protocol === 'http:' ? http : https;
      const forwardHeaders = {
        'User-Agent': req.headers['user-agent'] || 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive'
      };
      if (req.headers.range) {
        forwardHeaders['Range'] = req.headers.range;
      }

      const proxyReq = reqModule.request({
        protocol: parsed.protocol,
        hostname: parsed.hostname,
        port: parsed.port || (parsed.protocol === 'http:' ? 80 : 443),
        path: parsed.pathname + parsed.search,
        method: req.method,
        family: 4, // Force IPv4 to eliminate macOS IPv6 timeouts
        headers: forwardHeaders
      }, async (upstreamRes) => {
        if (upstreamRes.statusCode >= 400 && !isRetry) {
          proxyReq.destroy();
          ytdlp.invalidateStreamCache(videoId, quality);
          try {
            const freshStreams = await ytdlp.getBestStreamUrl(videoId, quality, true);
            const freshUrl = (quality === 'audio')
              ? (freshStreams.audioUrl || freshStreams.videoUrl)
              : (type === 'audio' ? freshStreams.audioUrl : freshStreams.videoUrl);
            if (freshUrl) {
              return forwardStream(freshUrl, true);
            }
          } catch (freshErr) {
            console.error('Failed to get fresh stream URL on retry:', freshErr);
          }
          if (!res.headersSent) {
            res.status(upstreamRes.statusCode).end();
          }
          return;
        }

        res.status(upstreamRes.statusCode);
        for (const [key, val] of Object.entries(upstreamRes.headers)) {
          const lower = key.toLowerCase();
          if (['content-range', 'content-length', 'content-type', 'accept-ranges'].includes(lower)) {
            res.setHeader(key, val);
          }
        }
        res.setHeader('Access-Control-Allow-Origin', '*');
        if (req.method === 'HEAD') {
          return res.end();
        }
        upstreamRes.on('error', () => {});
        upstreamRes.pipe(res);
      });

      proxyReq.on('error', async (err) => {
        if (!isRetry) {
          ytdlp.invalidateStreamCache(videoId, quality);
          try {
            const freshStreams = await ytdlp.getBestStreamUrl(videoId, quality, true);
            const freshUrl = (quality === 'audio')
              ? (freshStreams.audioUrl || freshStreams.videoUrl)
              : (type === 'audio' ? freshStreams.audioUrl : freshStreams.videoUrl);
            if (freshUrl) {
              return forwardStream(freshUrl, true);
            }
          } catch (e) {}
        }
        if (!res.headersSent) {
          res.status(502).end();
        }
      });

      req.on('close', () => {
        try { proxyReq.destroy(); } catch (e) {}
      });

      proxyReq.end();
    } catch (err) {
      if (!res.headersSent) res.status(500).send('Proxy error');
    }
  }

  try {
    const streams = await ytdlp.getBestStreamUrl(videoId, quality);
    let targetUrl = streams.videoUrl;
    if (quality === 'audio') {
      targetUrl = streams.audioUrl || streams.videoUrl;
    } else if (type === 'audio') {
      if (!streams.audioUrl) {
        return res.status(204).end();
      }
      targetUrl = streams.audioUrl;
    }
    if (!targetUrl) {
      return res.status(404).send('Stream not available');
    }
    forwardStream(targetUrl, false);
  } catch (err) {
    console.error('Error fetching stream URL:', err);
    if (!res.headersSent) res.status(500).send('Stream error');
  }
});

/**
 * POST /api/download
 * Start downloading video / MP3 to local ~/Downloads/YouTube_Adfree
 */
app.post('/api/download', (req, res) => {
  const { videoId, format, title } = req.body;
  if (!isValidVideoId(videoId)) {
    return res.status(400).json({ success: false, error: 'Valid 11-character YouTube video ID is required' });
  }
  const cleanFormat = sanitizeFormat(format);
  const cleanTitle = (typeof title === 'string')
    ? title.slice(0, 150).replace(/[^\w\s\u00C0-\u1EF9.,_() -]/gi, '').trim()
    : videoId;

  const downloadId = `${videoId}_${Date.now()}`;
  const downloadState = {
    id: downloadId,
    videoId,
    title: cleanTitle || videoId,
    format: cleanFormat,
    progress: 0,
    status: 'downloading',
    startTime: Date.now()
  };

  activeDownloads.set(downloadId, downloadState);

  const process = ytdlp.downloadMedia(
    videoId,
    cleanFormat,
    (progress) => {
      downloadState.progress = progress;
    },
    (info) => {
      downloadState.progress = 100;
      downloadState.status = 'completed';
      downloadState.savedTo = info.dir;
    },
    (err) => {
      downloadState.status = 'failed';
      downloadState.error = err.message;
    }
  );

  downloadState.process = process;

  res.json({ success: true, downloadId, state: downloadState });
});

/**
 * GET /api/downloads
 * Get all current and recent downloads
 */
app.get('/api/downloads', (req, res) => {
  const list = Array.from(activeDownloads.values()).map(d => {
    const { process, ...clean } = d;
    return clean;
  });
  res.json({ success: true, downloads: list, downloadDir: ytdlp.DOWNLOADS_DIR });
});

/**
 * POST /api/open-folder
 * Open ~/Downloads/YouTube_Adfree in macOS Finder
 */
app.post('/api/open-folder', (req, res) => {
  try {
    const { execFile } = require('child_process');
    execFile('open', [ytdlp.DOWNLOADS_DIR], (err) => {
      if (err) return res.status(500).json({ success: false, error: err.message });
      res.json({ success: true });
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * Fallback to index.html for SPA routes
 */
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Start server
if (!global.__serverStarted) {
  global.__serverStarted = true;
  app.listen(PORT, '127.0.0.1', () => {
    console.log(`=========================================`);
    console.log(`🚀 AuraTube Local Server running at:`);
    console.log(`👉 Web Browser: http://127.0.0.1:${PORT}`);
    console.log(`📁 Local Downloads: ${ytdlp.DOWNLOADS_DIR}`);
    console.log(`=========================================`);
  });
}

module.exports = app;
