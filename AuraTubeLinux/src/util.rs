//! Small shared helpers: HTTP, background work, image loading, formatting.

use gtk::prelude::*;
use gtk::{gdk, gio, glib};
use std::cell::RefCell;
use std::collections::HashMap;
use std::io::Read;
use std::sync::OnceLock;
use std::time::Duration;

pub const UA: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

pub fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(8))
            .timeout(Duration::from_secs(20))
            .user_agent(UA)
            .build()
    })
}

pub fn get_bytes(url: &str) -> Option<Vec<u8>> {
    let resp = agent().get(url).call().ok()?;
    let mut buf = Vec::new();
    resp.into_reader().take(64 * 1024 * 1024).read_to_end(&mut buf).ok()?;
    Some(buf)
}

pub fn get_json(url: &str) -> Option<serde_json::Value> {
    agent().get(url).call().ok()?.into_json().ok()
}

pub fn post_json(url: &str, body: &serde_json::Value) -> Option<serde_json::Value> {
    agent()
        .post(url)
        .set("Accept-Language", "vi,en;q=0.9")
        .send_json(body.clone())
        .ok()?
        .into_json()
        .ok()
}

/// Runs `work` on a worker thread and hands its result to `done` on the GTK main thread.
pub fn bg<T, F, D>(work: F, done: D)
where
    T: Send + 'static,
    F: FnOnce() -> T + Send + 'static,
    D: FnOnce(T) + 'static,
{
    glib::spawn_future_local(async move {
        if let Ok(v) = gio::spawn_blocking(work).await {
            done(v);
        }
    });
}

thread_local! {
    static IMAGE_CACHE: RefCell<HashMap<String, gdk::Texture>> = RefCell::new(HashMap::new());
}

/// Loads a remote image into a picture, with an in-memory cache.
pub fn load_image(pic: &gtk::Picture, url: &str) {
    if url.is_empty() {
        return;
    }
    if let Some(t) = IMAGE_CACHE.with(|c| c.borrow().get(url).cloned()) {
        pic.set_paintable(Some(&t));
        return;
    }
    let weak = pic.downgrade();
    let key = url.to_string();
    let u = url.to_string();
    bg(
        move || get_bytes(&u),
        move |bytes| {
            let Some(bytes) = bytes else { return };
            let Ok(tex) = gdk::Texture::from_bytes(&glib::Bytes::from_owned(bytes)) else { return };
            IMAGE_CACHE.with(|c| {
                let mut c = c.borrow_mut();
                if c.len() > 600 {
                    c.clear();
                }
                c.insert(key, tex.clone());
            });
            if let Some(p) = weak.upgrade() {
                p.set_paintable(Some(&tex));
            }
        },
    );
}

pub fn open_uri(uri: &str) {
    let _ = gio::AppInfo::launch_default_for_uri(uri, None::<&gio::AppLaunchContext>);
}

pub fn fmt_time(secs: f64) -> String {
    let s = if secs.is_finite() && secs > 0.0 { secs as u64 } else { 0 };
    let (h, m, s) = (s / 3600, (s % 3600) / 60, s % 60);
    if h > 0 {
        format!("{h}:{m:02}:{s:02}")
    } else {
        format!("{m}:{s:02}")
    }
}

/// Finds an executable by name on PATH.
pub fn which(name: &str) -> Option<std::path::PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|d| d.join(name))
        .find(|p| p.metadata().map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false))
}

pub fn label(text: &str, classes: &[&str]) -> gtk::Label {
    let l = gtk::Label::new(Some(text));
    l.set_xalign(0.0);
    for c in classes {
        l.add_css_class(c);
    }
    l
}
