/**
 * Invidious & SponsorBlock Service
 * Provides ultra-fast trending, search queries, and sponsor segment skip detection
 */

const INVIDIOUS_INSTANCES = [
  'https://inv.tux.pizza',
  'https://invidious.nerdvpn.de',
  'https://invidious.privacydev.net',
  'https://yt.artemislena.eu',
  'https://invidious.projectsegfau.lt'
];

let currentInstanceIndex = 0;

function getInstance() {
  return INVIDIOUS_INSTANCES[currentInstanceIndex % INVIDIOUS_INSTANCES.length];
}

function rotateInstance() {
  currentInstanceIndex = (currentInstanceIndex + 1) % INVIDIOUS_INSTANCES.length;
}

/**
 * Fetch trending videos
 */
async function getTrending(region = 'VN') {
  for (let i = 0; i < INVIDIOUS_INSTANCES.length; i++) {
    const instance = getInstance();
    try {
      const res = await fetch(`${instance}/api/v1/trending?region=${region}`, {
        signal: AbortSignal.timeout(1500)
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (Array.isArray(data) && data.length > 0) {
        return data.map(item => ({
          id: item.videoId,
          title: item.title,
          uploader: item.author,
          uploaderUrl: item.authorUrl,
          duration: item.lengthSeconds,
          viewCount: item.viewCount,
          publishedText: item.publishedText,
          thumbnail: item.videoThumbnails ? item.videoThumbnails[0]?.url : `https://i.ytimg.com/vi/${item.videoId}/hqdefault.jpg`
        }));
      }
    } catch (err) {
      console.warn(`Invidious instance ${instance} failed for trending:`, err.message);
      rotateInstance();
    }
  }
  return [];
}

/**
 * Quick search via Invidious API
 */
async function quickSearch(query, page = 1) {
  for (let i = 0; i < INVIDIOUS_INSTANCES.length; i++) {
    const instance = getInstance();
    try {
      const res = await fetch(`${instance}/api/v1/search?q=${encodeURIComponent(query)}&page=${page}&type=video`, {
        signal: AbortSignal.timeout(1500)
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (Array.isArray(data) && data.length > 0) {
        return data.filter(item => item.type === 'video' || item.videoId).map(item => ({
          id: item.videoId,
          title: item.title,
          uploader: item.author,
          duration: item.lengthSeconds,
          viewCount: item.viewCount,
          publishedText: item.publishedText,
          thumbnail: item.videoThumbnails ? item.videoThumbnails[0]?.url : `https://i.ytimg.com/vi/${item.videoId}/hqdefault.jpg`
        }));
      }
    } catch (err) {
      console.warn(`Invidious instance ${instance} failed for search:`, err.message);
      rotateInstance();
    }
  }
  return null; // Signals fallback to yt-dlp
}

/**
 * Fetch SponsorBlock segments to auto-skip promotional/sponsored sections
 */
async function getSponsorSegments(videoId) {
  try {
    const categories = JSON.stringify(['sponsor', 'selfpromo', 'interaction', 'intro', 'outro']);
    const url = `https://sponsor.ajay.app/api/skipSegments?videoID=${videoId}&categories=${encodeURIComponent(categories)}`;
    const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
    if (!res.ok) return [];
    const data = await res.json();
    return data.map(seg => ({
      category: seg.category,
      segment: seg.segment // [startTime, endTime]
    }));
  } catch (err) {
    return [];
  }
}

module.exports = {
  getTrending,
  quickSearch,
  getSponsorSegments
};
