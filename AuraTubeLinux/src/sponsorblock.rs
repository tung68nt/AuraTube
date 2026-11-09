//! SponsorBlock segments (port of SponsorBlockService.swift).

use crate::util::agent;
use std::time::Duration;

#[derive(Clone, Debug)]
pub struct Segment {
    pub category: String,
    pub start: f64,
    pub end: f64,
}

pub fn fetch(video_id: &str) -> Vec<Segment> {
    let Ok(resp) = agent()
        .get("https://sponsor.ajay.app/api/skipSegments")
        .timeout(Duration::from_secs(4))
        .query("videoID", video_id)
        .query("categories", r#"["sponsor","intro","outro","interaction","selfpromo"]"#)
        .call()
    else {
        return vec![];
    };
    let Ok(v) = resp.into_json::<serde_json::Value>() else { return vec![] };
    v.as_array()
        .map(|a| {
            a.iter()
                .filter_map(|s| {
                    let seg = s["segment"].as_array()?;
                    Some(Segment {
                        category: s["category"].as_str().unwrap_or("sponsor").into(),
                        start: seg.first()?.as_f64()?,
                        end: seg.get(1)?.as_f64()?,
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

pub fn label(category: &str) -> &'static str {
    match category {
        "intro" => "phần mở đầu",
        "outro" => "phần kết",
        "interaction" => "lời kêu gọi tương tác",
        "selfpromo" => "đoạn tự quảng bá",
        _ => "đoạn tài trợ",
    }
}
