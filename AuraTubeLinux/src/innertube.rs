//! YouTube InnerTube client (search, trending, channel, watch details, suggestions).
//! Ported from YTDLPService.swift / RecommendationService.swift: same endpoints, same
//! WEB client context (hl=vi, gl=VN), parsing done by walking the JSON tree.

use crate::util::{agent, post_json};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashSet;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Video {
    pub id: String,
    pub title: String,
    pub channel: String,
    pub channel_id: Option<String>,
    pub thumb: String,
    pub duration: String,
    pub views: String,
    pub published: String,
    pub is_short: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct Channel {
    pub id: String,
    pub title: String,
    pub avatar: String,
    #[serde(default)]
    pub subs: String,
}

#[derive(Default)]
pub struct Page {
    pub videos: Vec<Video>,
    pub shorts: Vec<Video>,
    pub continuation: Option<String>,
}

#[derive(Default, Clone)]
pub struct Details {
    pub title: String,
    pub channel: String,
    pub channel_id: Option<String>,
    pub channel_avatar: String,
    pub subs: String,
    pub views: String,
    pub date: String,
    pub description: String,
    pub related: Vec<Video>,
}

pub const FILTER_THIS_WEEK: &str = "EgQIAxAB";
const BASE: &str = "https://www.youtube.com/youtubei/v1/";

fn call(endpoint: &str, mut body: Value) -> Option<Value> {
    body["context"] = json!({
        "client": { "clientName": "WEB", "clientVersion": "2.20240101.00.00", "hl": "vi", "gl": "VN" }
    });
    post_json(&format!("{BASE}{endpoint}?prettyPrint=false"), &body)
}

// ---------------------------------------------------------------- JSON helpers

pub fn text(v: &Value) -> String {
    if let Some(s) = v.get("simpleText").and_then(Value::as_str) {
        return s.to_string();
    }
    if let Some(runs) = v.get("runs").and_then(Value::as_array) {
        return runs.iter().filter_map(|r| r.get("text").and_then(Value::as_str)).collect();
    }
    if let Some(s) = v.get("content").and_then(Value::as_str) {
        return s.to_string();
    }
    v.as_str().unwrap_or_default().to_string()
}

/// Depth-first search for the first value stored under `key`.
pub fn find_key<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    match v {
        Value::Object(m) => {
            if let Some(x) = m.get(key) {
                return Some(x);
            }
            m.values().find_map(|c| find_key(c, key))
        }
        Value::Array(a) => a.iter().find_map(|c| find_key(c, key)),
        _ => None,
    }
}

fn str_at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a str> {
    let mut cur = v;
    for p in path {
        cur = match p.parse::<usize>() {
            Ok(i) => cur.get(i)?,
            Err(_) => cur.get(*p)?,
        };
    }
    cur.as_str()
}

fn fix_url(u: &str) -> String {
    if u.starts_with("//") {
        format!("https:{u}")
    } else {
        u.to_string()
    }
}

fn last_thumb(v: &Value) -> Option<String> {
    v.as_array()?.last()?.get("url")?.as_str().map(fix_url)
}

fn default_thumb(id: &str) -> String {
    format!("https://i.ytimg.com/vi/{id}/hqdefault.jpg")
}

fn browse_id(v: &Value) -> Option<String> {
    find_key(v, "browseEndpoint")?.get("browseId")?.as_str().map(String::from)
}

// ---------------------------------------------------------------- renderers

fn parse_video_renderer(r: &Value) -> Option<Video> {
    let id = r.get("videoId")?.as_str()?;
    if id.len() != 11 {
        return None;
    }
    let title = text(&r["title"]);
    if title.is_empty() {
        return None;
    }
    let owner = ["ownerText", "longBylineText", "shortBylineText"]
        .iter()
        .map(|k| &r[*k])
        .find(|v| !v.is_null())
        .cloned()
        .unwrap_or(Value::Null);
    let mut views = text(&r["shortViewCountText"]);
    if views.is_empty() {
        views = text(&r["viewCountText"]);
    }
    Some(Video {
        id: id.into(),
        title,
        channel: text(&owner),
        channel_id: browse_id(&owner),
        thumb: last_thumb(&r["thumbnail"]["thumbnails"]).unwrap_or_else(|| default_thumb(id)),
        duration: text(&r["lengthText"]),
        views,
        published: text(&r["publishedTimeText"]),
        is_short: false,
    })
}

fn parse_lockup(r: &Value) -> Option<Video> {
    let id = r.get("contentId")?.as_str()?;
    if id.len() != 11 || r["contentType"].as_str() == Some("LOCKUP_CONTENT_TYPE_PLAYLIST") {
        return None;
    }
    let meta = &r["metadata"]["lockupMetadataViewModel"];
    let title = meta["title"]["content"].as_str().unwrap_or_default().to_string();
    if title.is_empty() {
        return None;
    }
    let rows = &meta["metadata"]["contentMetadataViewModel"]["metadataRows"];
    let part = |row: usize, i: usize| str_at(rows, &[&row.to_string(), "metadataParts", &i.to_string(), "text", "content"]).unwrap_or_default().to_string();
    let duration = find_key(&r["contentImage"], "thumbnailBadgeViewModel")
        .and_then(|b| b["text"].as_str())
        .unwrap_or_default()
        .to_string();
    let thumb = find_key(&r["contentImage"], "sources").and_then(last_thumb).unwrap_or_else(|| default_thumb(id));
    Some(Video {
        id: id.into(),
        title,
        channel: part(0, 0),
        channel_id: browse_id(&meta["image"]),
        thumb,
        duration,
        views: part(1, 0),
        published: part(1, 1),
        is_short: false,
    })
}

fn parse_reel(r: &Value) -> Option<Video> {
    let id = r.get("videoId")?.as_str()?;
    Some(Video {
        id: id.into(),
        title: text(&r["headline"]),
        views: text(&r["viewCountText"]),
        thumb: last_thumb(&r["thumbnail"]["thumbnails"]).unwrap_or_else(|| default_thumb(id)),
        is_short: true,
        ..Default::default()
    })
}

fn parse_shorts_lockup(r: &Value) -> Option<Video> {
    let id = find_key(r, "reelWatchEndpoint")?.get("videoId")?.as_str()?;
    Some(Video {
        id: id.into(),
        title: r["overlayMetadata"]["primaryText"]["content"].as_str().unwrap_or_default().into(),
        views: r["overlayMetadata"]["secondaryText"]["content"].as_str().unwrap_or_default().into(),
        thumb: str_at(r, &["thumbnail", "sources", "0", "url"]).map(fix_url).unwrap_or_else(|| default_thumb(id)),
        is_short: true,
        ..Default::default()
    })
}

fn walk(v: &Value, page: &mut Page, seen: &mut HashSet<String>) {
    match v {
        Value::Object(m) => {
            let mut push = |vid: Option<Video>, page: &mut Page| {
                if let Some(vid) = vid {
                    if seen.insert(vid.id.clone()) {
                        if vid.is_short {
                            page.shorts.push(vid)
                        } else {
                            page.videos.push(vid)
                        }
                    }
                }
            };
            for k in ["videoRenderer", "compactVideoRenderer", "gridVideoRenderer"] {
                if let Some(r) = m.get(k) {
                    push(parse_video_renderer(r), page);
                }
            }
            if let Some(r) = m.get("lockupViewModel") {
                push(parse_lockup(r), page);
            }
            if let Some(r) = m.get("reelItemRenderer") {
                push(parse_reel(r), page);
            }
            if let Some(r) = m.get("shortsLockupViewModel") {
                push(parse_shorts_lockup(r), page);
            }
            for c in m.values() {
                walk(c, page, seen);
            }
        }
        Value::Array(a) => a.iter().for_each(|c| walk(c, page, seen)),
        _ => {}
    }
}

fn parse_page(root: &Value) -> Page {
    let mut page = Page::default();
    let mut seen = HashSet::new();
    walk(root, &mut page, &mut seen);
    page.continuation = find_key(root, "continuationCommand")
        .and_then(|c| c["token"].as_str())
        .map(String::from);
    page
}

// ---------------------------------------------------------------- public API

pub fn search(query: &str, params: Option<&str>, continuation: Option<&str>) -> Page {
    let body = match continuation {
        Some(c) if !c.is_empty() => json!({ "continuation": c }),
        _ => {
            let mut b = json!({ "query": query });
            if let Some(p) = params.filter(|p| !p.is_empty()) {
                b["params"] = json!(p);
            }
            b
        }
    };
    call("search", body).map(|r| parse_page(&r)).unwrap_or_default()
}

/// Vietnam trending feed, built like RecommendationService.fetchVietnamTrendingFeed:
/// a few "pillar" searches filtered to this week, plus a Shorts shelf.
pub fn trending() -> Page {
    let pillars = [
        ("tin tức nóng hôm nay việt nam", Some(FILTER_THIS_WEEK)),
        ("review công nghệ mới nhất việt nam", Some(FILTER_THIS_WEEK)),
        ("vlog giải trí thịnh hành việt nam", Some(FILTER_THIS_WEEK)),
        ("mv ca nhạc mới nhất việt nam", Some(FILTER_THIS_WEEK)),
        // No date filter: InnerTube drops the Shorts shelf when filters are present.
        ("shorts trending việt nam viral triệu view", None),
    ];
    let results: Vec<Page> = std::thread::scope(|s| {
        let hs: Vec<_> = pillars.iter().map(|(q, p)| s.spawn(move || search(q, *p, None))).collect();
        hs.into_iter().map(|h| h.join().unwrap_or_default()).collect()
    });
    let mut out = Page::default();
    let mut seen = HashSet::new();
    let max = results.iter().map(|p| p.videos.len()).max().unwrap_or(0);
    for i in 0..max {
        for p in &results {
            if let Some(v) = p.videos.get(i) {
                if seen.insert(v.id.clone()) {
                    out.videos.push(v.clone());
                }
            }
        }
    }
    for p in &results {
        for v in &p.shorts {
            if seen.insert(v.id.clone()) {
                out.shorts.push(v.clone());
            }
        }
    }
    out
}

pub fn shorts_feed(continuation: Option<&str>) -> Page {
    let mut p = search("shorts trending việt nam", None, continuation);
    // Long-form results from a Shorts query are dropped; the feed is vertical only.
    p.videos.clear();
    p
}

pub fn suggestions(q: &str) -> Vec<String> {
    let Ok(resp) = agent()
        .get("https://suggestqueries-clients6.youtube.com/complete/search")
        .query("client", "youtube")
        .query("ds", "yt")
        .query("hl", "vi")
        .query("gl", "vn")
        .query("q", q)
        .call()
    else {
        return vec![];
    };
    let body = resp.into_string().unwrap_or_default();
    let (Some(a), Some(b)) = (body.find('['), body.rfind(']')) else { return vec![] };
    let Ok(v) = serde_json::from_str::<Value>(&body[a..=b]) else { return vec![] };
    v[1].as_array()
        .map(|arr| arr.iter().filter_map(|x| x[0].as_str().map(String::from)).take(10).collect())
        .unwrap_or_default()
}

pub fn resolve_channel(handle_or_url: &str) -> Option<String> {
    if handle_or_url.starts_with("UC") && handle_or_url.len() == 24 {
        return Some(handle_or_url.into());
    }
    let url = if handle_or_url.starts_with("http") {
        handle_or_url.to_string()
    } else {
        format!("https://www.youtube.com/{}", if handle_or_url.starts_with('@') { handle_or_url.to_string() } else { format!("@{handle_or_url}") })
    };
    let r = call("navigation/resolve_url", json!({ "url": url }))?;
    browse_id(&r["endpoint"])
}

pub fn channel(id: &str, continuation: Option<&str>) -> Option<(Channel, Page)> {
    let body = match continuation {
        Some(c) => json!({ "continuation": c }),
        None => json!({ "browseId": id, "params": "EgZ2aWRlb3PyBgQKAjoA" }),
    };
    let root = call("browse", body)?;
    let meta = &root["metadata"]["channelMetadataRenderer"];
    let mut ch = Channel {
        id: id.into(),
        title: meta["title"].as_str().unwrap_or_default().into(),
        avatar: last_thumb(&meta["avatar"]["thumbnails"]).unwrap_or_default(),
        subs: String::new(),
    };
    if let Some(h) = find_key(&root["header"], "pageHeaderViewModel") {
        if ch.title.is_empty() {
            ch.title = h["title"]["dynamicTextViewModel"]["text"]["content"].as_str().unwrap_or_default().into();
        }
        let mut strings = Vec::new();
        collect_strings(&h["metadata"], &mut strings);
        ch.subs = strings.into_iter().find(|s| s.contains("đăng ký") || s.contains("subscriber")).unwrap_or_default();
    } else if let Some(h) = root["header"].get("c4TabbedHeaderRenderer") {
        ch.subs = text(&h["subscriberCountText"]);
    }
    let mut page = parse_page(&root);
    for v in page.videos.iter_mut() {
        if v.channel.is_empty() {
            v.channel = ch.title.clone();
        }
        v.channel_id.get_or_insert_with(|| id.to_string());
    }
    Some((ch, page))
}

fn collect_strings(v: &Value, out: &mut Vec<String>) {
    match v {
        Value::String(s) => out.push(s.clone()),
        Value::Object(m) => m.values().for_each(|c| collect_strings(c, out)),
        Value::Array(a) => a.iter().for_each(|c| collect_strings(c, out)),
        _ => {}
    }
}

pub fn details(video_id: &str) -> Option<Details> {
    let root = call("next", json!({ "videoId": video_id }))?;
    let mut d = Details::default();
    if let Some(p) = find_key(&root, "videoPrimaryInfoRenderer") {
        d.title = text(&p["title"]);
        d.views = text(&p["viewCount"]["videoViewCountRenderer"]["viewCount"]);
        d.date = text(&p["dateText"]);
    }
    if let Some(s) = find_key(&root, "videoSecondaryInfoRenderer") {
        let owner = &s["owner"]["videoOwnerRenderer"];
        d.channel = text(&owner["title"]);
        d.channel_id = browse_id(&owner["navigationEndpoint"]);
        d.channel_avatar = last_thumb(&owner["thumbnail"]["thumbnails"]).unwrap_or_default();
        d.subs = text(&owner["subscriberCountText"]);
        d.description = s["attributedDescription"]["content"].as_str().map(String::from).unwrap_or_else(|| text(&s["description"]));
    }
    let secondary = &root["contents"]["twoColumnWatchNextResults"]["secondaryResults"];
    let mut page = parse_page(if secondary.is_null() { &root } else { secondary });
    page.videos.retain(|v| v.id != video_id);
    d.related = page.videos;
    Some(d)
}

/// What a pasted YouTube link or ID points to (port of YouTubeURLParser.swift).
pub enum Link {
    Video(String),
    Channel(String),
}

pub fn parse_link(input: &str) -> Option<Link> {
    let s = input.trim();
    let is_id = |x: &str| x.len() == 11 && x.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    if is_id(s) && !s.contains('.') {
        return None; // plain words of 11 chars are searches; IDs only via URLs
    }
    if !(s.contains("youtube.com") || s.contains("youtu.be")) {
        return None;
    }
    let after = |marker: &str| s.find(marker).map(|i| s[i + marker.len()..].chars().take_while(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_').collect::<String>());
    for m in ["v=", "youtu.be/", "/shorts/", "/live/", "/embed/"] {
        if let Some(id) = after(m).filter(|x| is_id(x)) {
            return Some(Link::Video(id));
        }
    }
    if let Some(id) = after("/channel/").filter(|x| x.starts_with("UC")) {
        return Some(Link::Channel(id));
    }
    if let Some(i) = s.find("/@") {
        let handle: String = s[i + 1..].chars().take_while(|c| !matches!(c, '/' | '?' | '#')).collect();
        return Some(Link::Channel(handle));
    }
    None
}
