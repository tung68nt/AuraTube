//! yt-dlp management (port of YTDLPBinary.swift) and stream URL extraction
//! (port of YTDLPService.getStreamInfo).
//!
//! * Uses the app-managed copy in ~/.local/share/AuraTube/bin/yt-dlp, falling back to the
//!   copy bundled in the .deb (/usr/lib/auratube/yt-dlp) or one on PATH.
//! * Downloads the standalone `yt-dlp_linux` build when missing; refreshes every 3 days.
//! * Always passes `--js-runtimes`; installs deno when neither deno nor node exists.
//!   Without a JS runtime YouTube only exposes a few formats and yt-dlp fails with
//!   "Requested format is not available".

use crate::util::{agent, which};
use std::io::Read;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

const UPDATE_INTERVAL: Duration = Duration::from_secs(3 * 24 * 3600);
static INSTALL_LOCK: Mutex<()> = Mutex::new(());
static JS_ARGS: Mutex<Option<Vec<String>>> = Mutex::new(None);

pub fn bin_dir() -> PathBuf {
    gtk::glib::user_data_dir().join("AuraTube").join("bin")
}

fn managed() -> PathBuf {
    bin_dir().join("yt-dlp")
}

fn download_url() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64"
    } else {
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"
    }
}

/// ELF binary or a script with a shebang, and not a small HTML error page.
fn is_valid(p: &Path) -> bool {
    let Ok(meta) = p.metadata() else { return false };
    if !meta.is_file() || meta.len() < 1024 || meta.permissions().mode() & 0o111 == 0 {
        return false;
    }
    let mut head = [0u8; 4];
    std::fs::File::open(p).and_then(|mut f| f.read_exact(&mut head)).is_ok() && (head == [0x7f, b'E', b'L', b'F'] || head.starts_with(b"#!"))
}

fn candidates() -> Vec<PathBuf> {
    let mut v = vec![managed(), PathBuf::from("/usr/lib/auratube/yt-dlp"), PathBuf::from("/opt/auratube/yt-dlp")];
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            v.push(dir.join("yt-dlp"));
            v.push(dir.join("../lib/auratube/yt-dlp"));
        }
    }
    if let Some(p) = which("yt-dlp") {
        v.push(p);
    }
    v
}

pub fn existing() -> Option<PathBuf> {
    candidates().into_iter().find(|p| is_valid(p))
}

pub fn resolve() -> Result<PathBuf, String> {
    match existing() {
        Some(p) => Ok(p),
        None => install(false),
    }
}

pub fn version() -> Option<String> {
    let out = Command::new(existing()?).arg("--version").output().ok()?;
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Called at launch: installs if missing, refreshes the managed copy when it is old
/// (YouTube changes often break outdated yt-dlp).
pub fn prepare_in_background() {
    std::thread::spawn(|| {
        let _ = js_runtime_args();
        let m = managed();
        if !is_valid(&m) {
            let _ = install(false);
            return;
        }
        let old = m
            .metadata()
            .and_then(|md| md.modified())
            .ok()
            .and_then(|t| SystemTime::now().duration_since(t).ok())
            .map(|age| age > UPDATE_INTERVAL)
            .unwrap_or(false);
        if old {
            let _ = install(true);
        }
    });
}

fn download_to(url: &str, dest: &Path) -> Result<(), String> {
    let resp = agent().get(url).timeout(Duration::from_secs(600)).call().map_err(|e| format!("Tải thất bại: {e}"))?;
    let mut f = std::fs::File::create(dest).map_err(|e| e.to_string())?;
    std::io::copy(&mut resp.into_reader(), &mut f).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn install(force: bool) -> Result<PathBuf, String> {
    let _guard = INSTALL_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let dest = managed();
    if !force && is_valid(&dest) {
        return Ok(dest);
    }
    std::fs::create_dir_all(bin_dir()).map_err(|e| e.to_string())?;
    let staged = bin_dir().join("yt-dlp.new");
    let mut last_err = String::from("Không thể tải yt-dlp. Vui lòng kiểm tra kết nối mạng.");
    for attempt in 0..3 {
        let _ = std::fs::remove_file(&staged);
        match download_to(download_url(), &staged) {
            Ok(()) => {
                let _ = std::fs::set_permissions(&staged, std::fs::Permissions::from_mode(0o755));
                if is_valid(&staged) {
                    std::fs::rename(&staged, &dest).map_err(|e| e.to_string())?;
                    return Ok(dest);
                }
                last_err = "File yt-dlp tải về không hợp lệ".into();
            }
            Err(e) => last_err = e,
        }
        std::thread::sleep(Duration::from_millis(1500 * (attempt + 1)));
    }
    // A failed refresh should not hide a still-working older copy.
    existing().ok_or(last_err)
}

// ---------------------------------------------------------------- JS runtime

fn managed_deno() -> PathBuf {
    bin_dir().join("deno")
}

fn existing_js_runtime() -> Option<(&'static str, PathBuf)> {
    let mut denos = vec![managed_deno()];
    if let Some(home) = std::env::var_os("HOME") {
        denos.push(PathBuf::from(home).join(".deno/bin/deno"));
    }
    denos.extend(which("deno"));
    if let Some(p) = denos.into_iter().find(|p| is_valid(p)) {
        return Some(("deno", p));
    }
    which("node").or_else(|| which("nodejs")).map(|p| ("node", p))
}

fn install_deno() -> Option<PathBuf> {
    let asset = if cfg!(target_arch = "aarch64") { "deno-aarch64-unknown-linux-gnu.zip" } else { "deno-x86_64-unknown-linux-gnu.zip" };
    let url = format!("https://github.com/denoland/deno/releases/latest/download/{asset}");
    std::fs::create_dir_all(bin_dir()).ok()?;
    let zip_path = bin_dir().join("deno.zip");
    for attempt in 0..3 {
        if download_to(&url, &zip_path).is_ok() {
            let ok = (|| -> Option<()> {
                let f = std::fs::File::open(&zip_path).ok()?;
                let mut ar = zip::ZipArchive::new(f).ok()?;
                let mut entry = ar.by_name("deno").ok()?;
                let tmp = bin_dir().join("deno.new");
                let mut out = std::fs::File::create(&tmp).ok()?;
                std::io::copy(&mut entry, &mut out).ok()?;
                drop(out);
                std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755)).ok()?;
                std::fs::rename(&tmp, managed_deno()).ok()
            })();
            let _ = std::fs::remove_file(&zip_path);
            if ok.is_some() && is_valid(&managed_deno()) {
                return Some(managed_deno());
            }
        }
        std::thread::sleep(Duration::from_secs(2 * (attempt + 1)));
    }
    None
}

/// `--js-runtimes` arguments for yt-dlp (installs deno on first use if needed).
pub fn js_runtime_args() -> Vec<String> {
    let mut cached = JS_ARGS.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(a) = cached.as_ref() {
        return a.clone();
    }
    let args = match existing_js_runtime() {
        Some((name, p)) => vec!["--js-runtimes".into(), format!("{name}:{}", p.display())],
        None => match install_deno() {
            Some(p) => vec!["--js-runtimes".into(), format!("deno:{}", p.display())],
            None => vec![],
        },
    };
    if !args.is_empty() {
        *cached = Some(args.clone());
    }
    args
}

pub fn ffmpeg_dir() -> Option<PathBuf> {
    which("ffmpeg").and_then(|p| p.parent().map(Path::to_path_buf))
}

/// Builds a yt-dlp command with the JS runtime already set.
pub fn command() -> Result<Command, String> {
    let bin = resolve()?;
    let mut c = Command::new(bin);
    c.args(js_runtime_args());
    Ok(c)
}

fn run(args: &[&str]) -> Result<String, String> {
    let out = command()?.args(args).output().map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).to_string())
    } else {
        let err = String::from_utf8_lossy(&out.stderr);
        Err(err.lines().rev().find(|l| l.contains("ERROR")).unwrap_or(err.trim()).to_string())
    }
}

/// Returns (video-or-combined URL, optional separate audio URL).
pub fn stream_urls(video_id: &str, quality: &str) -> Result<(String, Option<String>), String> {
    if video_id.len() != 11 || !video_id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        return Err("ID video không hợp lệ".into());
    }
    let filter = match quality {
        "audio" => "bestaudio[protocol=https]/bestaudio/140/best",
        "mini" | "360" => "best[height<=360][protocol=m3u8_native]/best[height<=360][protocol=m3u8]/bestvideo[height<=360]+bestaudio/best",
        "shorts" => "bestvideo[height<=1280][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=1280][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=1280]+bestaudio/best",
        "720" => "best[height<=720][protocol=m3u8_native]/best[height<=720][protocol=m3u8]/bestvideo[height<=720]+bestaudio/best",
        _ => "best[height<=1080][protocol=m3u8_native]/best[height<=1080][protocol=m3u8]/best[protocol=m3u8_native]/best[protocol=m3u8]/bestvideo+bestaudio/best",
    };
    let url = format!("https://www.youtube.com/watch?v={video_id}");
    let fetch = |f: &str| run(&["--get-url", "-f", f, "--no-warnings", "--no-playlist", "--", &url]);
    let out = match fetch(&format!("{filter}/bv*+ba/b")) {
        Err(e) if e.to_lowercase().contains("format is not available") => {
            // Last resort: any playable format YouTube offers right now.
            fetch(if quality == "audio" { "ba/b" } else { "b/bv*+ba/bv*" })?
        }
        r => r?,
    };
    let mut lines = out.lines().map(str::trim).filter(|l| l.starts_with("http"));
    let first = lines.next().ok_or("Không lấy được link phát video")?.to_string();
    Ok((first, lines.next().map(String::from)))
}
