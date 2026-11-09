//! Downloads (port of DownloadManager.swift): MP4 or MP3 through yt-dlp, with the same
//! no-ffmpeg fallbacks (single-file MP4 / original M4A audio).

use crate::innertube::Video;
use crate::util::{label, open_uri};
use crate::ytdlp;
use gtk::prelude::*;
use gtk::glib;
use std::io::{BufRead, BufReader};
use std::process::Stdio;

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Mp4,
    Mp3,
}

enum Msg {
    Progress(f64, String),
    Done(Result<String, String>),
}

pub struct Downloads {
    pub root: gtk::ScrolledWindow,
    list: gtk::ListBox,
}

impl Downloads {
    pub fn new() -> Self {
        let list = gtk::ListBox::new();
        list.set_selection_mode(gtk::SelectionMode::None);
        list.add_css_class("boxed-list");
        list.set_placeholder(Some(&{
            let l = label("Chưa có video nào được tải xuống.", &["dim-label"]);
            l.set_margin_top(24);
            l.set_margin_bottom(24);
            l.set_xalign(0.5);
            l
        }));
        let clamp = adw::Clamp::new();
        clamp.set_maximum_size(820);
        let b = gtk::Box::new(gtk::Orientation::Vertical, 12);
        b.set_margin_top(24);
        b.set_margin_bottom(24);
        b.set_margin_start(16);
        b.set_margin_end(16);
        b.append(&label("Tải xuống", &["title-1"]));
        b.append(&list);
        clamp.set_child(Some(&b));
        let root = gtk::ScrolledWindow::new();
        root.set_child(Some(&clamp));
        Self { root, list }
    }

    pub fn start(&self, v: &Video, kind: Kind, dir: &str, quality: &str) {
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        row.set_margin_top(10);
        row.set_margin_bottom(10);
        row.set_margin_start(12);
        row.set_margin_end(12);
        let info = gtk::Box::new(gtk::Orientation::Vertical, 4);
        info.set_hexpand(true);
        let title = label(&format!("{} ({})", v.title, if kind == Kind::Mp3 { "MP3" } else { "MP4" }), &["heading"]);
        title.set_ellipsize(gtk::pango::EllipsizeMode::End);
        let status = label("Đang chuẩn bị…", &["dim-label", "caption"]);
        let bar = gtk::ProgressBar::new();
        info.append(&title);
        info.append(&bar);
        info.append(&status);
        let open = gtk::Button::from_icon_name("folder-open-symbolic");
        open.set_valign(gtk::Align::Center);
        open.set_tooltip_text(Some("Mở thư mục"));
        open.add_css_class("flat");
        let d = dir.to_string();
        open.connect_clicked(move |_| open_uri(&glib::filename_to_uri(&d, None).map(|u| u.to_string()).unwrap_or_default()));
        row.append(&info);
        row.append(&open);
        self.list.prepend(&row);

        let (tx, rx) = async_channel::unbounded::<Msg>();
        let (id, dir, quality) = (v.id.clone(), dir.to_string(), quality.to_string());
        std::thread::spawn(move || {
            let res = run_download(&id, kind, &dir, &quality, &tx);
            let _ = tx.send_blocking(Msg::Done(res));
        });
        glib::spawn_future_local(async move {
            while let Ok(m) = rx.recv().await {
                match m {
                    Msg::Progress(f, s) => {
                        bar.set_fraction(f);
                        status.set_text(&s);
                    }
                    Msg::Done(Ok(path)) => {
                        bar.set_fraction(1.0);
                        status.set_text(&format!("Đã tải xong: {path}"));
                    }
                    Msg::Done(Err(e)) => {
                        status.set_text(&format!("Lỗi: {e}"));
                        status.add_css_class("error");
                    }
                }
            }
        });
    }
}

fn run_download(id: &str, kind: Kind, dir: &str, q: &str, tx: &async_channel::Sender<Msg>) -> Result<String, String> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let ffmpeg = ytdlp::ffmpeg_dir();
    let primary: Vec<String> = match (kind, ffmpeg.is_some()) {
        (Kind::Mp3, true) => ["-f", "bestaudio/best", "-x", "--audio-format", "mp3", "--audio-quality", "0", "--embed-metadata"].map(String::from).to_vec(),
        // No ffmpeg to convert to MP3: save the original M4A audio instead of failing.
        (Kind::Mp3, false) => vec!["-f".into(), "bestaudio[ext=m4a]/bestaudio/b".into()],
        (Kind::Mp4, true) => vec![
            "-f".into(),
            format!("bestvideo[vcodec^=avc1][height<={q}]+bestaudio[ext=m4a]/bestvideo[ext=mp4][height<={q}]+bestaudio[ext=m4a]/bestvideo[height<={q}]+bestaudio/best[height<={q}]/bv*+ba/b"),
            "--merge-output-format".into(),
            "mp4".into(),
            "--postprocessor-args".into(),
            "Merger:-movflags +faststart".into(),
        ],
        // No ffmpeg to merge separate streams: take the best single-file MP4.
        (Kind::Mp4, false) => vec!["-f".into(), format!("best[ext=mp4][height<={q}]/best[ext=mp4]/b/bv*")],
    };
    let fallback: Vec<String> = vec!["-f".into(), if kind == Kind::Mp3 { "ba/b".into() } else { "b/bv*+ba/bv*".into() }];
    let mut last = String::new();
    for fmt in [primary, fallback] {
        let mut cmd = ytdlp::command()?;
        cmd.args(["--no-playlist", "--newline", "--progress", "--print", "after_move:filepath", "-o"])
            .arg(format!("{dir}/%(title)s [%(id)s].%(ext)s"));
        if let Some(ff) = &ffmpeg {
            cmd.arg("--ffmpeg-location").arg(ff);
        }
        cmd.args(&fmt).arg("--").arg(format!("https://www.youtube.com/watch?v={id}"));
        let mut child = cmd.stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().map_err(|e| e.to_string())?;
        let stderr = child.stderr.take();
        let err_reader = std::thread::spawn(move || {
            let mut s = String::new();
            if let Some(e) = stderr {
                for l in BufReader::new(e).lines().map_while(Result::ok) {
                    s = l;
                }
            }
            s
        });
        let mut path = String::new();
        if let Some(out) = child.stdout.take() {
            for line in BufReader::new(out).lines().map_while(Result::ok) {
                if line.starts_with('/') {
                    path = line;
                } else if let Some(rest) = line.strip_prefix("[download]") {
                    if let Some(pct) = rest.split_whitespace().next().and_then(|p| p.strip_suffix('%')).and_then(|p| p.parse::<f64>().ok()) {
                        let _ = tx.send_blocking(Msg::Progress(pct / 100.0, rest.trim().to_string()));
                    }
                } else if line.starts_with("[Merger]") || line.starts_with("[ExtractAudio]") {
                    let _ = tx.send_blocking(Msg::Progress(1.0, "Đang xử lý…".into()));
                }
            }
        }
        let status = child.wait().map_err(|e| e.to_string())?;
        last = err_reader.join().unwrap_or_default();
        if status.success() {
            return Ok(path);
        }
        if !last.to_lowercase().contains("format is not available") {
            break;
        }
    }
    Err(if last.is_empty() { "yt-dlp thất bại".into() } else { last })
}
