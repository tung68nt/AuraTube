//! Update check (port of UpdateService.swift for Linux). Reads `version-linux.json` from
//! main, falling back to `version.json`'s `linuxDownloadUrl`, and points the user to the
//! new .deb on the releases page. No in-place self-update.

use crate::util::get_json;

const REPO_RAW: &str = "https://raw.githubusercontent.com/tung68nt/AuraTube/main";
pub const RELEASES: &str = "https://github.com/tung68nt/AuraTube/releases/latest";

#[derive(Clone, Debug)]
pub struct UpdateInfo {
    pub version: String,
    pub title: String,
    pub notes: String,
    pub url: String,
}

fn parse(v: &str) -> Vec<u64> {
    v.trim_start_matches('v').split('.').map(|p| p.parse().unwrap_or(0)).collect()
}

pub fn is_newer(remote: &str, local: &str) -> bool {
    parse(remote) > parse(local)
}

pub fn check() -> Option<UpdateInfo> {
    let current = env!("CARGO_PKG_VERSION");
    let (json, url_key) = match get_json(&format!("{REPO_RAW}/version-linux.json")) {
        Some(j) => (j, "downloadUrl"),
        None => (get_json(&format!("{REPO_RAW}/version.json"))?, "linuxDownloadUrl"),
    };
    let version = json["version"].as_str()?.to_string();
    if !is_newer(&version, current) {
        return None;
    }
    // version.json without a Linux URL means the Linux build is not published yet.
    let url = json[url_key].as_str()?.to_string();
    Some(UpdateInfo {
        title: json["title"].as_str().map(String::from).unwrap_or_else(|| format!("AuraTube v{version}")),
        notes: json["releaseNotes"].as_str().unwrap_or_default().into(),
        version,
        url,
    })
}
