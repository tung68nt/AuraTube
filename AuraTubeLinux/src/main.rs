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
    gtk::glib::set_application_name("AuraTube");
    gtk::glib::set_prgname(Some("auratube"));
    let app = adw::Application::builder().application_id("io.github.tung68nt.AuraTube").build();
    app.connect_activate(app::App::build);
    app.run()
}
