//! Network-speed based auto quality (port of NetworkSpeedService.swift's idea):
//! time a couple of image downloads from YouTube's CDN and map Mbps to a resolution.

use crate::util::agent;
use std::io::Read;
use std::time::Instant;

const PROBES: [&str; 2] = [
    "https://i.ytimg.com/vi/aqz-KE-bpKQ/maxresdefault.jpg",
    "https://i.ytimg.com/vi/jNQXAC9IVRw/hqdefault.jpg",
];

/// Returns measured Mbps (0 when offline).
pub fn measure_mbps() -> f64 {
    let start = Instant::now();
    let mut bytes = 0usize;
    for url in PROBES {
        if let Ok(resp) = agent().get(url).call() {
            let mut buf = Vec::new();
            if resp.into_reader().read_to_end(&mut buf).is_ok() {
                bytes += buf.len();
            }
        }
    }
    let secs = start.elapsed().as_secs_f64().max(0.001);
    bytes as f64 * 8.0 / secs / 1_000_000.0
}

pub fn quality_for(mbps: f64) -> &'static str {
    if mbps >= 8.0 {
        "1080"
    } else if mbps >= 3.0 {
        "720"
    } else {
        "360"
    }
}
