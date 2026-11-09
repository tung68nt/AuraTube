//! AuraTube for Linux — native GTK4/libadwaita + GStreamer port of the macOS app.
#![allow(deprecated)]

mod app;
mod downloads;
mod innertube;
mod player;
mod settings;
mod speed;
mod sponsorblock;
mod tray;
mod update;
mod util;
mod widgets;
mod ytdlp;

use adw::prelude::*;

fn main() -> gtk::glib::ExitCode {
    if let Err(e) = gst::init() {
        eprintln!("auratube: không khởi tạo được GStreamer: {e}");
    }
    if std::env::args().any(|a| a == "--selftest") {
        return selftest();
    }
    gtk::glib::set_application_name("AuraTube");
    gtk::glib::set_prgname(Some("auratube"));
    let app = adw::Application::builder().application_id("io.github.tung68nt.AuraTube").build();
    app.connect_activate(app::App::build);
    app.run()
}

/// Headless end-to-end check used by CI: InnerTube, SponsorBlock, yt-dlp and the real
/// GStreamer pipeline from `player.rs` (separate video + audio decodebins).
fn selftest() -> gtk::glib::ExitCode {
    let mut ok = true;
    let mut check = |name: &str, pass: bool, info: String| {
        println!("[{}] {name}: {info}", if pass { "OK" } else { "FAIL" });
        ok &= pass;
    };
    let t = innertube::trending();
    check("trending", !t.videos.is_empty(), format!("{} videos, {} shorts", t.videos.len(), t.shorts.len()));
    let s = innertube::search("lofi hip hop", None, None);
    check("search", !s.videos.is_empty(), format!("{} videos, continuation={}", s.videos.len(), s.continuation.is_some()));
    if let Some(c) = s.continuation.as_deref() {
        let p = innertube::search("", None, Some(c));
        check("search continuation", !p.videos.is_empty(), format!("{} videos", p.videos.len()));
    }
    let id = "jNQXAC9IVRw";
    let d = innertube::details(id).unwrap_or_default();
    check("details", !d.title.is_empty(), format!("{:?} by {:?}, {} related", d.title, d.channel, d.related.len()));
    let ch = d.channel_id.as_deref().and_then(|c| innertube::channel(c, None));
    check("channel", ch.as_ref().map(|c| !c.1.videos.is_empty()).unwrap_or(false), ch.map(|c| format!("{:?} {:?}, {} videos", c.0.title, c.0.subs, c.1.videos.len())).unwrap_or_default());
    let h = innertube::resolve_channel("@YouTube");
    check("resolve handle", h.is_some(), format!("{h:?}"));
    check("suggestions", !innertube::suggestions("son tung").is_empty(), String::new());
    let sh = innertube::shorts_feed(None);
    check("shorts feed", !sh.shorts.is_empty(), format!("{} shorts", sh.shorts.len()));
    println!("sponsorblock: {} segments", sponsorblock::fetch("dQw4w9WgXcQ").len());
    println!("yt-dlp: {:?} at {:?}, js: {:?}", ytdlp::version(), ytdlp::existing(), ytdlp::js_runtime_args());
    // YouTube often blocks datacenter IPs, so stream extraction is reported, not fatal.
    match ytdlp::stream_urls(id, "720") {
        Ok((v, a)) => {
            println!("[OK] stream urls: separate audio={}", a.is_some());
            pipeline_test("youtube", &v, a.as_deref());
        }
        Err(e) => println!("[WARN] stream urls: {e}"),
    }
    // Public samples, so the pipeline is exercised even when YouTube blocks the runner.
    let mp4 = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4";
    ok &= pipeline_test("separate video+audio", mp4, Some(mp4));
    ok &= pipeline_test("hls", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", None);
    if ok {
        gtk::glib::ExitCode::SUCCESS
    } else {
        gtk::glib::ExitCode::FAILURE
    }
}

fn pipeline_test(name: &str, video: &str, audio: Option<&str>) -> bool {
    use std::cell::RefCell;
    use std::rc::Rc;
    let ctx = gtk::glib::MainContext::default();
    let p = player::Player::new();
    let result: Rc<RefCell<Option<String>>> = Rc::default();
    let r = result.clone();
    p.set_handler(move |e| {
        *r.borrow_mut() = Some(match e {
            player::Event::Ready => "ready".into(),
            player::Event::Eos => "eos".into(),
            player::Event::Error(m) => format!("error: {m}"),
        })
    });
    p.load(video, audio, 3.0);
    let start = std::time::Instant::now();
    // Wait past the initial seek (first AsyncDone) for the Ready that follows it.
    while result.borrow().is_none() && start.elapsed().as_secs() < 40 {
        ctx.iteration(false);
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let r = result.borrow().clone().unwrap_or_else(|| "timeout".into());
    let pass = r == "ready";
    println!("[{}] player {name}: {r}, position {:.1}s / {:.0}s", if pass { "OK" } else { "FAIL" }, p.position(), p.duration());
    p.stop();
    pass
}

#[cfg(test)]
mod tests {
    use crate::innertube::{parse_link, Link};

    #[test]
    fn links_and_versions() {
        assert!(matches!(parse_link("https://youtu.be/jNQXAC9IVRw?t=3"), Some(Link::Video(v)) if v == "jNQXAC9IVRw"));
        assert!(matches!(parse_link("https://www.youtube.com/shorts/jNQXAC9IVRw"), Some(Link::Video(_))));
        assert!(matches!(parse_link("https://www.youtube.com/@MrBeast/videos"), Some(Link::Channel(c)) if c == "@MrBeast"));
        assert!(parse_link("nhac tre").is_none());
        assert!(crate::update::is_newer("2.1.12", "2.1.11"));
        assert!(!crate::update::is_newer("2.1.9", "2.1.11"));
    }
}
