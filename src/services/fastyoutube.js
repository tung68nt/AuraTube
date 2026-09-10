/**
 * Fast YouTube Scraper & InnerTube Service
 * High-performance, sub-second responses for Search & Trending
 * Strictly forces IPv4 to prevent macOS IPv6 DNS timeouts
 */

const dns = require('node:dns');
try {
  dns.setDefaultResultOrder('ipv4first');
} catch (e) {}

try {
  const { setGlobalDispatcher, Agent } = require('undici');
  setGlobalDispatcher(new Agent({
    connect: {
      family: 4
    },
    keepAliveTimeout: 30000,
    maxSockets: 50
  }));
} catch (e) {}

const MODERN_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

function extractAllVideos(obj, results = []) {
  if (!obj || typeof obj !== 'object') return results;
  if (obj.videoId && (obj.title || obj.headline)) {
    const title = obj.title?.runs?.map(r => r.text).join('') || obj.title?.simpleText || obj.headline?.simpleText || '';
    const uploader = obj.ownerText?.runs?.[0]?.text || obj.shortBylineText?.runs?.[0]?.text || '';
    const duration = obj.lengthText?.simpleText || '';
    const viewCount = obj.viewCountText?.simpleText || obj.shortViewCountText?.simpleText || '';
    const publishedTime = obj.publishedTimeText?.simpleText || '';
    const thumb = obj.thumbnail?.thumbnails?.slice(-1)[0]?.url || (`https://i.ytimg.com/vi/${obj.videoId}/hqdefault.jpg`);
    let avatar = obj.channelThumbnailSupportedRenderers?.channelThumbnailWithLinkRenderer?.thumbnail?.thumbnails?.[0]?.url || '';
    if (avatar.startsWith('//')) avatar = 'https:' + avatar;
    const description = obj.detailedMetadataSnippets?.[0]?.snippetText?.runs?.map(r => r.text).join('') || obj.descriptionSnippet?.runs?.map(r => r.text).join('') || '';

    if (title && obj.videoId.length === 11) {
      if (!results.some(v => v.id === obj.videoId)) {
        results.push({
          id: obj.videoId,
          title,
          uploader: uploader || 'YouTube',
          avatar,
          duration,
          viewCount,
          publishedTime,
          description,
          thumbnail: thumb,
          url: `https://www.youtube.com/watch?v=${obj.videoId}`
        });
      }
    }
  }
  for (const k of Object.keys(obj)) {
    extractAllVideos(obj[k], results);
  }
  return results;
}

function findChannelRenderer(obj) {
  if (!obj || typeof obj !== 'object') return null;

  // 1. Traditional channelRenderer
  if (obj.channelRenderer) {
    const ch = obj.channelRenderer;
    let avatar = ch.thumbnail?.thumbnails?.slice(-1)[0]?.url || '';
    if (avatar.startsWith('//')) avatar = 'https:' + avatar;
    const subText = ch.subscriberCountText?.simpleText || ch.videoCountText?.simpleText || '';
    const handle = ch.navigationEndpoint?.browseEndpoint?.canonicalBaseUrl || '';
    return {
      id: ch.channelId,
      title: ch.title?.simpleText || ch.title?.runs?.[0]?.text || '',
      handle,
      subscribers: subText,
      description: ch.descriptionSnippet?.runs?.map(r => r.text).join('') || '',
      avatar
    };
  }

  // 2. Modern officialCardViewModel (e.g. verified artists / major channels)
  if (obj.officialCardViewModel) {
    const card = obj.officialCardViewModel;
    const title = card.header?.titleRenderer?.title?.runs?.[0]?.text || '';
    const avatar = card.header?.thumbnail?.thumbnails?.slice(-1)[0]?.url || '';
    const handle = card.header?.subtitle?.runs?.[0]?.text || '';
    const browseId = card.rendererContext?.commandContext?.onTap?.innertubeCommand?.browseEndpoint?.browseId || '';
    if (title) {
      return {
        id: browseId,
        title,
        handle,
        subscribers: '',
        description: '',
        avatar
      };
    }
  }

  for (const k of Object.keys(obj)) {
    const found = findChannelRenderer(obj[k]);
    if (found) return found;
  }
  return null;
}

/**
 * High-speed InnerTube search (JSON response in ~1.5s)
 */
async function searchInnerTube(query) {
  const res = await fetch('https://www.youtube.com/youtubei/v1/search?prettyPrint=false', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': MODERN_UA,
      'Accept-Language': 'vi,en;q=0.9'
    },
    body: JSON.stringify({
      context: {
        client: {
          clientName: 'WEB',
          clientVersion: '2.20240101.00.00',
          hl: 'vi',
          gl: 'VN'
        }
      },
      query
    }),
    signal: AbortSignal.timeout(6500)
  });

  if (!res.ok) {
    throw new Error(`InnerTube HTTP ${res.status}`);
  }

  const data = await res.json();
  const channel = findChannelRenderer(data);
  const videos = extractAllVideos(data);
  return { channel, videos };
}

/**
 * Scrape desktop YouTube HTML as backup
 */
async function searchDesktopHtml(query) {
  const url = `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}`;
  const res = await fetch(url, {
    headers: {
      'User-Agent': MODERN_UA,
      'Accept-Language': 'vi,en;q=0.9'
    },
    signal: AbortSignal.timeout(6500)
  });

  const html = await res.text();
  const match = html.match(/var ytInitialData = ({.*?});<\/script>/);
  if (!match) return { channel: null, videos: [] };

  const json = JSON.parse(match[1]);
  const channel = findChannelRenderer(json);
  const videos = extractAllVideos(json);
  return { channel, videos };
}

/**
 * Search YouTube with multi-layer fallback
 */
async function searchYouTube(query) {
  // Layer 1: InnerTube API
  try {
    const innerTubeRes = await searchInnerTube(query);
    if (innerTubeRes.videos && innerTubeRes.videos.length > 0) {
      return innerTubeRes;
    }
  } catch (err) {
    console.warn('[searchYouTube] InnerTube failed, trying desktop scrape:', err.message);
  }

  // Layer 2: Desktop HTML Scrape
  try {
    const desktopRes = await searchDesktopHtml(query);
    if (desktopRes.videos && desktopRes.videos.length > 0) {
      return desktopRes;
    }
  } catch (err) {
    console.warn('[searchYouTube] Desktop scrape failed, trying yt-dlp fallback:', err.message);
  }

  // Layer 3: yt-dlp flat-playlist search fallback
  try {
    const ytdlp = require('./ytdlp');
    const items = await ytdlp.searchVideos(query, 20);
    if (items && items.length > 0) {
      return { channel: null, videos: items };
    }
  } catch (err) {
    console.error('[searchYouTube] yt-dlp fallback failed:', err.message);
  }

  return { channel: null, videos: [] };
}

async function getTrendingVideos(cookie = null) {
  try {
    const headers = {
      'User-Agent': MODERN_UA,
      'Accept-Language': 'vi,en;q=0.9'
    };
    if (cookie) headers['Cookie'] = cookie;

    // Use InnerTube search for trending topics when not logged in
    if (!cookie) {
      try {
        const innerTubeRes = await searchInnerTube('nhạc việt hot trending hôm nay');
        if (innerTubeRes.videos && innerTubeRes.videos.length > 0) {
          return innerTubeRes.videos;
        }
      } catch (e) {}
    }

    const url = cookie ? 'https://www.youtube.com' : `https://www.youtube.com/results?search_query=${encodeURIComponent('nhạc việt hot trending hôm nay')}`;
    const res = await fetch(url, { headers, signal: AbortSignal.timeout(7000) });

    const html = await res.text();
    const match = html.match(/var ytInitialData = ({.*?});<\/script>/);
    if (!match) return [];

    const json = JSON.parse(match[1]);
    return extractAllVideos(json);
  } catch (err) {
    console.error('getTrendingVideos error:', err);
    return [];
  }
}

async function getSubscriptions(cookie) {
  if (!cookie) return [];
  try {
    const url = 'https://www.youtube.com/feed/subscriptions';
    const res = await fetch(url, {
      headers: {
        'User-Agent': MODERN_UA,
        'Accept-Language': 'vi,en;q=0.9',
        'Cookie': cookie
      },
      signal: AbortSignal.timeout(7000)
    });

    const html = await res.text();
    const match = html.match(/var ytInitialData = ({.*?});<\/script>/);
    if (!match) return [];

    const json = JSON.parse(match[1]);
    return extractAllVideos(json);
  } catch (err) {
    console.error('getSubscriptions error:', err);
    return [];
  }
}

module.exports = {
  searchYouTube,
  getTrendingVideos,
  getSubscriptions,
  extractAllVideos,
  findChannelRenderer
};
