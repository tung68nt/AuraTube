//! Reusable widgets: video cards, the video grid and the player view with its controls
//! overlay (port of PlayerControlOverlay.swift).

use crate::app::app;
use crate::innertube::Video;
use crate::util::{fmt_time, label, load_image};
use gtk::prelude::*;
use gtk::{glib, pango};
use std::cell::{Cell, RefCell};
use std::rc::Rc;

pub const QUALITIES: [&str; 4] = ["auto", "1080", "720", "360"];
pub const QUALITY_LABELS: [&str; 4] = ["Tự động", "1080p", "720p", "360p"];
pub const SPEEDS: [f64; 6] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

pub fn clear_box(b: &gtk::Box) {
    while let Some(c) = b.first_child() {
        b.remove(&c);
    }
}

pub fn video_card(v: &Video) -> gtk::Widget {
    let (w, h) = if v.is_short { (190, 338) } else { (320, 180) };
    let card = gtk::Box::new(gtk::Orientation::Vertical, 6);
    card.set_width_request(w);
    card.add_css_class("video-card");
    card.set_cursor_from_name(Some("pointer"));

    let pic = gtk::Picture::new();
    pic.set_size_request(w, h);
    pic.set_can_shrink(true);
    pic.add_css_class("thumb");
    pic.set_overflow(gtk::Overflow::Hidden);
    load_image(&pic, &v.thumb);
    let ov = gtk::Overlay::new();
    ov.set_child(Some(&pic));
    if !v.duration.is_empty() {
        let d = gtk::Label::new(Some(&v.duration));
        d.add_css_class("duration");
        d.set_halign(gtk::Align::End);
        d.set_valign(gtk::Align::End);
        d.set_margin_end(6);
        d.set_margin_bottom(6);
        ov.add_overlay(&d);
    }
    card.append(&ov);

    let title = label(&v.title, &["video-title"]);
    title.set_wrap(true);
    title.set_wrap_mode(pango::WrapMode::WordChar);
    title.set_lines(2);
    title.set_ellipsize(pango::EllipsizeMode::End);
    title.set_max_width_chars(if v.is_short { 18 } else { 32 });
    card.append(&title);

    if !v.channel.is_empty() {
        let ch = gtk::Button::with_label(&v.channel);
        ch.add_css_class("flat");
        ch.add_css_class("channel-link");
        ch.set_halign(gtk::Align::Start);
        if let Some(l) = ch.child().and_downcast::<gtk::Label>() {
            l.set_ellipsize(pango::EllipsizeMode::End);
            l.set_xalign(0.0);
        }
        let (id, name) = (v.channel_id.clone(), v.channel.clone());
        ch.connect_clicked(move |_| {
            if let Some(id) = &id {
                app().open_channel(id, &name);
            }
        });
        card.append(&ch);
    }
    let meta = [v.views.as_str(), v.published.as_str()].iter().filter(|s| !s.is_empty()).cloned().collect::<Vec<_>>().join(" • ");
    if !meta.is_empty() {
        let m = label(&meta, &["dim-label", "caption"]);
        m.set_ellipsize(pango::EllipsizeMode::End);
        card.append(&m);
    }

    let click = gtk::GestureClick::new();
    let video = v.clone();
    click.connect_released(move |_, _, _, _| {
        let a = app();
        if video.is_short {
            a.open_short(video.clone());
        } else {
            a.open_video(video.clone());
        }
    });
    ov.add_controller(click);
    let click2 = gtk::GestureClick::new();
    let video = v.clone();
    click2.connect_released(move |_, _, _, _| {
        if video.is_short {
            app().open_short(video.clone())
        } else {
            app().open_video(video.clone())
        }
    });
    title.add_controller(click2);
    card.upcast()
}

/// Horizontal shelf of Shorts cards.
pub fn shorts_shelf(shorts: &[Video]) -> gtk::Widget {
    let b = gtk::Box::new(gtk::Orientation::Vertical, 8);
    b.append(&label("Shorts", &["title-3"]));
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    for v in shorts.iter().take(20) {
        row.append(&video_card(v));
    }
    let sc = gtk::ScrolledWindow::new();
    sc.set_policy(gtk::PolicyType::Automatic, gtk::PolicyType::Never);
    sc.set_child(Some(&row));
    b.append(&sc);
    b.set_margin_bottom(12);
    b.upcast()
}

pub struct VideoGrid {
    pub root: gtk::ScrolledWindow,
    pub header: gtk::Box,
    flow: gtk::FlowBox,
    spinner: gtk::Spinner,
    empty: gtk::Label,
    pub continuation: RefCell<Option<String>>,
    loading: Cell<bool>,
    on_more: RefCell<Option<Rc<dyn Fn(String)>>>,
}

impl VideoGrid {
    pub fn new() -> Rc<Self> {
        let flow = gtk::FlowBox::new();
        flow.set_selection_mode(gtk::SelectionMode::None);
        flow.set_homogeneous(true);
        flow.set_max_children_per_line(8);
        flow.set_min_children_per_line(1);
        flow.set_row_spacing(20);
        flow.set_column_spacing(16);
        flow.set_valign(gtk::Align::Start);
        let header = gtk::Box::new(gtk::Orientation::Vertical, 12);
        let spinner = gtk::Spinner::new();
        spinner.set_size_request(32, 32);
        spinner.set_margin_top(24);
        spinner.set_visible(false);
        let empty = label("Không có video nào.", &["dim-label"]);
        empty.set_xalign(0.5);
        empty.set_margin_top(48);
        empty.set_visible(false);
        let vb = gtk::Box::new(gtk::Orientation::Vertical, 12);
        for m in [&vb] {
            m.set_margin_top(20);
            m.set_margin_bottom(20);
            m.set_margin_start(24);
            m.set_margin_end(24);
        }
        vb.append(&header);
        vb.append(&flow);
        vb.append(&spinner);
        vb.append(&empty);
        let root = gtk::ScrolledWindow::new();
        root.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
        root.set_child(Some(&vb));
        root.set_vexpand(true);
        let g = Rc::new(Self { root, header, flow, spinner, empty, continuation: RefCell::new(None), loading: Cell::new(false), on_more: RefCell::new(None) });
        let weak = Rc::downgrade(&g);
        g.root.connect_edge_reached(move |_, pos| {
            let Some(g) = weak.upgrade() else { return };
            if pos != gtk::PositionType::Bottom || g.loading.get() {
                return;
            }
            let cont = g.continuation.borrow().clone();
            let more = g.on_more.borrow().clone();
            if let (Some(c), Some(f)) = (cont, more) {
                f(c);
            }
        });
        g
    }

    pub fn set_on_more(&self, f: impl Fn(String) + 'static) {
        *self.on_more.borrow_mut() = Some(Rc::new(f));
    }

    pub fn clear(&self) {
        while let Some(c) = self.flow.first_child() {
            self.flow.remove(&c);
        }
        clear_box(&self.header);
        *self.continuation.borrow_mut() = None;
        self.root.vadjustment().set_value(0.0);
        self.empty.set_visible(false);
    }

    pub fn set_loading(&self, on: bool) {
        self.loading.set(on);
        self.spinner.set_visible(on);
        self.spinner.set_spinning(on);
        if on {
            self.empty.set_visible(false);
        }
    }

    pub fn append(&self, videos: &[Video], continuation: Option<String>) {
        for v in videos {
            self.flow.insert(&video_card(v), -1);
        }
        *self.continuation.borrow_mut() = continuation;
        self.set_loading(false);
        self.empty.set_visible(self.flow.first_child().is_none());
    }
}

pub struct PlayerView {
    pub root: gtk::Overlay,
    pub picture: gtk::Picture,
    play_btn: gtk::Button,
    scale: gtk::Scale,
    time: gtk::Label,
    spinner: gtk::Spinner,
    status: gtk::Label,
    pub quality: gtk::DropDown,
    revealer: gtk::Revealer,
    hide_src: RefCell<Option<glib::SourceId>>,
    updating: Cell<bool>,
}

impl PlayerView {
    pub fn new(shorts: bool) -> Rc<Self> {
        let picture = gtk::Picture::new();
        picture.set_can_shrink(true);
        picture.set_hexpand(true);
        picture.set_vexpand(true);
        let bg = gtk::Box::new(gtk::Orientation::Vertical, 0);
        bg.add_css_class("player-bg");
        bg.append(&picture);
        let root = gtk::Overlay::new();
        root.set_child(Some(&bg));
        root.set_overflow(gtk::Overflow::Hidden);

        let spinner = gtk::Spinner::new();
        spinner.set_size_request(48, 48);
        spinner.set_halign(gtk::Align::Center);
        spinner.set_valign(gtk::Align::Center);
        spinner.set_can_target(false);
        root.add_overlay(&spinner);
        let status = gtk::Label::new(None);
        status.add_css_class("player-status");
        status.set_wrap(true);
        status.set_halign(gtk::Align::Center);
        status.set_valign(gtk::Align::Center);
        status.set_visible(false);
        root.add_overlay(&status);

        let controls = gtk::Box::new(gtk::Orientation::Vertical, 2);
        controls.add_css_class("player-controls");
        let scale = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 1.0, 1.0);
        scale.set_draw_value(false);
        scale.set_hexpand(true);
        controls.append(&scale);
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let play_btn = gtk::Button::from_icon_name("media-playback-start-symbolic");
        play_btn.add_css_class("flat");
        play_btn.set_tooltip_text(Some("Phát/Tạm dừng (Space)"));
        let time = gtk::Label::new(Some("0:00 / 0:00"));
        time.add_css_class("numeric");
        let vol_icon = gtk::Image::from_icon_name("audio-volume-high-symbolic");
        let volume = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 1.0, 0.05);
        volume.set_draw_value(false);
        volume.set_width_request(90);
        let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        spacer.set_hexpand(true);
        let speed = gtk::DropDown::from_strings(&SPEEDS.map(|s| format!("{s}x")).iter().map(String::as_str).collect::<Vec<_>>());
        speed.set_selected(2);
        speed.set_tooltip_text(Some("Tốc độ phát"));
        let quality = gtk::DropDown::from_strings(&QUALITY_LABELS);
        quality.set_tooltip_text(Some("Chất lượng"));
        let mini = gtk::Button::from_icon_name("view-restore-symbolic");
        mini.add_css_class("flat");
        mini.set_tooltip_text(Some("Trình phát mini"));
        let full = gtk::Button::from_icon_name("view-fullscreen-symbolic");
        full.add_css_class("flat");
        full.set_tooltip_text(Some("Toàn màn hình (F)"));
        row.append(&play_btn);
        row.append(&time);
        row.append(&vol_icon);
        row.append(&volume);
        row.append(&spacer);
        row.append(&speed);
        if !shorts {
            row.append(&quality);
            row.append(&mini);
        }
        row.append(&full);
        controls.append(&row);
        let revealer = gtk::Revealer::new();
        revealer.set_transition_type(gtk::RevealerTransitionType::Crossfade);
        revealer.set_valign(gtk::Align::End);
        revealer.set_child(Some(&controls));
        revealer.set_reveal_child(true);
        root.add_overlay(&revealer);

        let v = Rc::new(Self { root, picture, play_btn, scale, time, spinner, status, quality, revealer, hide_src: RefCell::new(None), updating: Cell::new(false) });

        v.play_btn.connect_clicked(|_| app().player.toggle());
        v.scale.connect_change_value(|_, _, val| {
            app().player.seek(val);
            glib::Propagation::Proceed
        });
        volume.set_value(app_volume());
        volume.connect_value_changed(|s| app().set_volume(s.value()));
        speed.connect_selected_notify(|d| app().player.set_rate(SPEEDS[d.selected() as usize % SPEEDS.len()]));
        let weak = Rc::downgrade(&v);
        v.quality.connect_selected_notify(move |d| {
            if weak.upgrade().map(|v| v.updating.get()).unwrap_or(true) {
                return;
            }
            app().change_quality(QUALITIES[d.selected() as usize % QUALITIES.len()]);
        });
        mini.connect_clicked(|_| app().toggle_mini());
        full.connect_clicked(|_| app().toggle_fullscreen());

        let click = gtk::GestureClick::new();
        click.connect_pressed(|_, n, _, _| {
            let a = app();
            a.player.toggle();
            if n == 2 {
                a.toggle_fullscreen();
            }
        });
        v.picture.add_controller(click);
        let motion = gtk::EventControllerMotion::new();
        let weak = Rc::downgrade(&v);
        motion.connect_motion(move |_, _, _| {
            if let Some(v) = weak.upgrade() {
                v.poke();
            }
        });
        v.root.add_controller(motion);
        v
    }

    /// Shows the controls and hides them again after 3 s of no mouse movement.
    pub fn poke(self: &Rc<Self>) {
        self.revealer.set_reveal_child(true);
        if let Some(id) = self.hide_src.borrow_mut().take() {
            id.remove();
        }
        let weak = Rc::downgrade(self);
        let id = glib::timeout_add_local_once(std::time::Duration::from_secs(3), move || {
            if let Some(v) = weak.upgrade() {
                v.hide_src.borrow_mut().take();
                if app().player.is_playing() {
                    v.revealer.set_reveal_child(false);
                }
            }
        });
        *self.hide_src.borrow_mut() = Some(id);
    }

    pub fn set_quality(&self, q: &str) {
        self.updating.set(true);
        self.quality.set_selected(QUALITIES.iter().position(|x| *x == q).unwrap_or(0) as u32);
        self.updating.set(false);
    }

    pub fn set_loading(&self, on: bool) {
        self.spinner.set_visible(on);
        self.spinner.set_spinning(on);
        if on {
            self.status.set_visible(false);
        }
    }

    pub fn set_error(&self, msg: &str) {
        self.set_loading(false);
        self.status.set_text(&format!("Không phát được video:\n{msg}"));
        self.status.set_visible(true);
    }

    pub fn update(&self, pos: f64, dur: f64, playing: bool) {
        self.scale.set_range(0.0, dur.max(1.0));
        self.scale.set_value(pos);
        self.time.set_text(&format!("{} / {}", fmt_time(pos), fmt_time(dur)));
        self.play_btn.set_icon_name(if playing { "media-playback-pause-symbolic" } else { "media-playback-start-symbolic" });
        if !playing {
            self.revealer.set_reveal_child(true);
        }
    }
}

fn app_volume() -> f64 {
    crate::app::try_app().map(|a| a.player.volume()).unwrap_or(1.0)
}
