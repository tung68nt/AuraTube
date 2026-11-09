//! Persistent settings (~/.config/AuraTube/settings.json), including local subscriptions
//! (port of ChannelSubscriptionManager.swift).

use crate::innertube::Channel;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// "auto" (network speed), "1080", "720" or "360".
    pub quality: String,
    pub sponsorblock: bool,
    pub autoplay: bool,
    pub run_in_background: bool,
    pub download_dir: String,
    pub download_quality: String,
    pub volume: f64,
    pub subscriptions: Vec<Channel>,
    pub history: Vec<String>,
}

impl Default for Settings {
    fn default() -> Self {
        let dl = gtk::glib::user_special_dir(gtk::glib::UserDirectory::Downloads)
            .unwrap_or_else(|| gtk::glib::home_dir().join("Downloads"));
        Self {
            quality: "auto".into(),
            sponsorblock: true,
            autoplay: true,
            run_in_background: false,
            download_dir: dl.join("AuraTube").to_string_lossy().into(),
            download_quality: "1080".into(),
            volume: 1.0,
            subscriptions: vec![],
            history: vec![],
        }
    }
}

fn path() -> PathBuf {
    gtk::glib::user_config_dir().join("AuraTube").join("settings.json")
}

impl Settings {
    pub fn load() -> Self {
        std::fs::read_to_string(path()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
    }

    pub fn save(&self) {
        let p = path();
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        if let Ok(s) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(p, s);
        }
    }

    pub fn is_subscribed(&self, id: &str) -> bool {
        self.subscriptions.iter().any(|c| c.id == id)
    }

    pub fn toggle_subscription(&mut self, ch: Channel) -> bool {
        if self.is_subscribed(&ch.id) {
            self.subscriptions.retain(|c| c.id != ch.id);
            false
        } else {
            self.subscriptions.insert(0, ch);
            true
        }
    }
}
