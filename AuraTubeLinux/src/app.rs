//! Application shell: window, navigation, pages and playback flow
//! (ports ContentView/HomeView/WatchView/ChannelDetailView/NativeShortsFeedView/
//! SettingsSheetView/MenuBarController behavior).

use crate::downloads::{Downloads, Kind};
use crate::innertube::{self, Channel, Details, Link, Video};
use crate::player::{Event, Player};
use crate::settings::Settings;
use crate::sponsorblock::{self, Segment};
use crate::util::{bg, label, load_image, open_uri, which};
use crate::widgets::{clear_box, shorts_shelf, PlayerView, VideoGrid, QUALITIES};
use crate::{speed, update, ytdlp};
use adw::prelude::*;
use gtk::{gio, glib, pango};
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::{Duration, Instant};

thread_local! {
    static APP: RefCell<Option<Rc<App>>> = const { RefCell::new(None) };
}

pub fn app() -> Rc<App> {
    try_app().expect("app not initialised")
}

pub fn try_app() -> Option<Rc<App>> {
    APP.with(|a| a.borrow().clone())
}

#[derive(Clone, Copy, PartialEq)]
pub enum Mode {
    Idle,
    Watch,
    Shorts,
}

/// Commands coming from MPRIS media keys and the tray icon (other threads).
pub enum Cmd {
    Show,
    Play,
    Pause,
    Toggle,
    Next,
    Prev,
    Seek(f64),
    Quit,
}

pub struct WatchPage {
    root: gtk::Box,
    view: Rc<PlayerView>,
    details: gtk::Box,
    side: gtk::ScrolledWindow,
    title: gtk::Label,
    channel_btn: gtk::Button,
    avatar: gtk::Picture,
    subs: gtk::Label,
    sub_btn: gtk::Button,
    meta: gtk::Label,
    desc: gtk::Label,
    related: gtk::Box,
}

pub struct ShortsPage {
    root: gtk::Box,
    view: Rc<PlayerView>,
    title: gtk::Label,
    meta: gtk::Label,
    items: RefCell<Vec<Video>>,
    idx: Cell<usize>,
    cont: RefCell<Option<String>>,
    loading: Cell<bool>,
    last_scroll: Cell<Option<Instant>>,
}

pub struct App {
    pub gapp: adw::Application,
    pub window: adw::ApplicationWindow,
    pub player: Rc<Player>,
    pub settings: RefCell<Settings>,
    stack: gtk::Stack,
    history: RefCell<Vec<String>>,
    back_btn: gtk::Button,
    header: adw::HeaderBar,
    sidebar: gtk::Box,
    toasts: adw::ToastOverlay,
    update_bar: gtk::Revealer,
    update_label: gtk::Label,
    update_url: RefCell<String>,
    search_entry: gtk::SearchEntry,
    suggest_pop: gtk::Popover,
    suggest_list: gtk::ListBox,
    home: Rc<VideoGrid>,
    search: Rc<VideoGrid>,
    channel: Rc<VideoGrid>,
    subs: Rc<VideoGrid>,
    watch: WatchPage,
    shorts: ShortsPage,
    downloads: Downloads,
    mode: Cell<Mode>,
    current: RefCell<Option<Video>>,
    current_details: RefCell<Option<Details>>,
    related: RefCell<Vec<Video>>,
    segments: RefCell<Vec<Segment>>,
    token: Cell<u64>,
    auto_quality: RefCell<String>,
    mini: RefCell<Option<gtk::Window>>,
    media: RefCell<Option<souvlaki::MediaControls>>,
    last_playing: Cell<Option<bool>>,
    search_query: RefCell<String>,
    channel_id: RefCell<String>,
    channel_info: RefCell<Option<Channel>>,
    home_loaded: Cell<bool>,
}

const CSS: &str = r#"
.player-bg { background-color: black; }
.player-controls { background-image: linear-gradient(to top, rgba(0,0,0,0.85), rgba(0,0,0,0)); padding: 18px 12px 6px 12px; }
.player-controls, .player-controls label, .player-controls button { color: white; }
.player-status { color: white; background-color: rgba(0,0,0,0.6); padding: 12px; border-radius: 8px; }
.thumb { border-radius: 12px; background-color: alpha(currentColor, 0.08); }
.duration { background-color: rgba(0,0,0,0.8); color: white; border-radius: 4px; padding: 1px 5px; font-size: 11px; font-weight: bold; }
.video-title { font-weight: bold; }
.channel-link { padding: 0; min-height: 0; font-size: 13px; }
.avatar { border-radius: 9999px; }
.update-bar { background-color: @accent_bg_color; color: @accent_fg_color; padding: 6px 12px; }
.sidebar-pane { background-color: @view_bg_color; }
"#;

fn icon_button(icon: &str, tip: &str) -> gtk::Button {
    let b = gtk::Button::from_icon_name(icon);
    b.set_tooltip_text(Some(tip));
    b
}

impl App {
    pub fn build(gapp: &adw::Application) {
        if let Some(a) = try_app() {
            a.window.present();
            return;
        }
        let provider = gtk::CssProvider::new();
        provider.load_from_data(CSS);
        if let Some(display) = gtk::gdk::Display::default() {
            gtk::style_context_add_provider_for_display(&display, &provider, gtk::STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        let settings = Settings::load();
        let player = Player::new();
        player.set_volume(settings.volume);

        let window = adw::ApplicationWindow::new(gapp);
        window.set_title(Some("AuraTube"));
        window.set_default_size(1320, 860);
        window.set_icon_name(Some("auratube"));

        // Header
        let header = adw::HeaderBar::new();
        let back_btn = icon_button("go-previous-symbolic", "Quay lại");
        back_btn.set_visible(false);
        header.pack_start(&back_btn);
        let search_entry = gtk::SearchEntry::new();
        search_entry.set_placeholder_text(Some("Tìm kiếm hoặc dán link YouTube"));
        search_entry.set_width_request(460);
        header.set_title_widget(Some(&search_entry));
        let menu = gio::Menu::new();
        menu.append(Some("Mở trang phát hành"), Some("app.releases"));
        menu.append(Some("Kiểm tra cập nhật"), Some("app.check-update"));
        menu.append(Some("Giới thiệu AuraTube"), Some("app.about"));
        menu.append(Some("Thoát"), Some("app.quit"));
        let menu_btn = gtk::MenuButton::new();
        menu_btn.set_icon_name("open-menu-symbolic");
        menu_btn.set_menu_model(Some(&menu));
        header.pack_end(&menu_btn);

        let suggest_list = gtk::ListBox::new();
        suggest_list.set_selection_mode(gtk::SelectionMode::None);
        let suggest_pop = gtk::Popover::new();
        suggest_pop.set_child(Some(&suggest_list));
        suggest_pop.set_autohide(false);
        suggest_pop.set_has_arrow(false);
        suggest_pop.set_position(gtk::PositionType::Bottom);
        suggest_pop.set_parent(&search_entry);

        // Update bar
        let update_label = gtk::Label::new(None);
        update_label.set_hexpand(true);
        update_label.set_xalign(0.0);
        let ub = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        ub.add_css_class("update-bar");
        let dl_btn = gtk::Button::with_label("Tải bản mới");
        let close_btn = gtk::Button::from_icon_name("window-close-symbolic");
        close_btn.add_css_class("flat");
        ub.append(&update_label);
        ub.append(&dl_btn);
        ub.append(&close_btn);
        let update_bar = gtk::Revealer::new();
        update_bar.set_child(Some(&ub));

        // Sidebar
        let nav = gtk::ListBox::new();
        nav.add_css_class("navigation-sidebar");
        let entries = [
            ("go-home-symbolic", "Trang chủ", "home"),
            ("view-continuous-symbolic", "Shorts", "shorts"),
            ("starred-symbolic", "Kênh đăng ký", "subs"),
            ("media-playback-start-symbolic", "Đang phát", "watch"),
            ("folder-download-symbolic", "Tải xuống", "downloads"),
            ("emblem-system-symbolic", "Cài đặt", "settings"),
        ];
        for (icon, text, _) in entries {
            let r = gtk::Box::new(gtk::Orientation::Horizontal, 12);
            r.set_margin_top(6);
            r.set_margin_bottom(6);
            r.set_margin_start(6);
            r.append(&gtk::Image::from_icon_name(icon));
            r.append(&gtk::Label::new(Some(text)));
            nav.append(&r);
        }
        let sidebar = gtk::Box::new(gtk::Orientation::Vertical, 0);
        sidebar.add_css_class("sidebar-pane");
        sidebar.set_width_request(210);
        let logo = label("AuraTube", &["title-2"]);
        logo.set_margin_start(18);
        logo.set_margin_top(14);
        logo.set_margin_bottom(8);
        sidebar.append(&logo);
        sidebar.append(&nav);

        // Pages
        let stack = gtk::Stack::new();
        stack.set_hexpand(true);
        stack.set_transition_type(gtk::StackTransitionType::Crossfade);
        let home = VideoGrid::new();
        let search = VideoGrid::new();
        let channel = VideoGrid::new();
        let subs = VideoGrid::new();
        let watch = build_watch_page();
        let shorts = build_shorts_page();
        let downloads = Downloads::new();
        stack.add_named(&home.root, Some("home"));
        stack.add_named(&search.root, Some("search"));
        stack.add_named(&channel.root, Some("channel"));
        stack.add_named(&subs.root, Some("subs"));
        stack.add_named(&watch.root, Some("watch"));
        stack.add_named(&shorts.root, Some("shorts"));
        stack.add_named(&downloads.root, Some("downloads"));

        let body = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        body.append(&sidebar);
        body.append(&gtk::Separator::new(gtk::Orientation::Vertical));
        body.append(&stack);
        body.set_vexpand(true);
        let main = gtk::Box::new(gtk::Orientation::Vertical, 0);
        main.append(&header);
        main.append(&update_bar);
        main.append(&body);
        let toasts = adw::ToastOverlay::new();
        toasts.set_child(Some(&main));
        window.set_content(Some(&toasts));

        let a = Rc::new(App {
            gapp: gapp.clone(),
            window,
            player,
            settings: RefCell::new(settings),
            stack,
            history: RefCell::new(vec![]),
            back_btn,
            header,
            sidebar,
            toasts,
            update_bar,
            update_label,
            update_url: RefCell::new(update::RELEASES.into()),
            search_entry,
            suggest_pop,
            suggest_list,
            home,
            search,
            channel,
            subs,
            watch,
            shorts,
            downloads,
            mode: Cell::new(Mode::Idle),
            current: RefCell::new(None),
            current_details: RefCell::new(None),
            related: RefCell::new(vec![]),
            segments: RefCell::new(vec![]),
            token: Cell::new(0),
            auto_quality: RefCell::new("720".into()),
            mini: RefCell::new(None),
            media: RefCell::new(None),
            last_playing: Cell::new(None),
            search_query: RefCell::new(String::new()),
            channel_id: RefCell::new(String::new()),
            channel_info: RefCell::new(None),
            home_loaded: Cell::new(false),
        });
        APP.with(|x| *x.borrow_mut() = Some(a.clone()));

        // Settings page needs `app()` for its callbacks.
        let settings_page = build_settings_page();
        a.stack.add_named(&settings_page, Some("settings"));

        // Wiring
        nav.connect_row_activated(move |_, row| {
            let name = entries[row.index().max(0) as usize].2;
            app().navigate(name);
        });
        a.back_btn.connect_clicked(|_| app().back());
        dl_btn.connect_clicked(|_| open_uri(&app().update_url.borrow()));
        close_btn.connect_clicked(|_| app().update_bar.set_reveal_child(false));
        a.search_entry.connect_activate(|e| {
            let q = e.text().to_string();
            app().suggest_pop.popdown();
            app().search(&q);
        });
        a.search_entry.connect_search_changed(|e| app().load_suggestions(&e.text()));
        a.search_entry.connect_stop_search(|_| app().suggest_pop.popdown());
        a.suggest_list.connect_row_activated(|_, row| {
            let text = row.child().and_downcast::<gtk::Label>().map(|l| l.text().to_string()).unwrap_or_default();
            let a = app();
            a.suggest_pop.popdown();
            a.search_entry.set_text(&text);
            a.search(&text);
        });
        a.home.set_on_more(|_| {});
        a.search.set_on_more(|cont| {
            let a = app();
            a.search.set_loading(true);
            let q = a.search_query.borrow().clone();
            bg(move || innertube::search(&q, None, Some(&cont)), |p| app().search.append(&p.videos, p.continuation));
        });
        a.channel.set_on_more(|cont| {
            let a = app();
            a.channel.set_loading(true);
            let id = a.channel_id.borrow().clone();
            bg(move || innertube::channel(&id, Some(&cont)), |r| {
                let a = app();
                match r {
                    Some((_, p)) => a.channel.append(&p.videos, p.continuation),
                    None => a.channel.set_loading(false),
                }
            });
        });
        a.player.set_handler(|e| app().on_player_event(e));
        a.setup_actions();
        a.setup_keys();
        a.setup_media_controls();
        a.window.connect_close_request(|w| {
            let a = app();
            if a.settings.borrow().run_in_background {
                w.set_visible(false);
                a.toast("AuraTube vẫn chạy nền");
                glib::Propagation::Stop
            } else {
                a.player.stop();
                if let Some(m) = a.mini.borrow_mut().take() {
                    m.destroy();
                }
                glib::Propagation::Proceed
            }
        });
        a.window.connect_fullscreened_notify(|w| app().on_fullscreen(w.is_fullscreen()));
        glib::timeout_add_local(Duration::from_millis(250), || {
            if let Some(a) = try_app() {
                a.tick();
            }
            glib::ControlFlow::Continue
        });

        // Background work at launch
        ytdlp::prepare_in_background();
        bg(speed::measure_mbps, |mbps| {
            let a = app();
            *a.auto_quality.borrow_mut() = speed::quality_for(mbps).into();
            eprintln!("auratube: network {mbps:.1} Mbps → auto quality {}p", a.auto_quality.borrow());
        });
        glib::timeout_add_local_once(Duration::from_secs(4), || app().check_update(false));

        a.navigate("home");
        a.window.present();
    }

    pub fn toast(&self, msg: &str) {
        self.toasts.add_toast(adw::Toast::new(msg));
    }

    // ------------------------------------------------------------ navigation

    pub fn navigate(&self, name: &str) {
        let cur = self.stack.visible_child_name().map(|s| s.to_string());
        if cur.as_deref() == Some(name) {
            self.on_page_shown(name);
            return;
        }
        if let Some(c) = cur {
            if c != "home" || !self.history.borrow().is_empty() || name != "home" {
                self.history.borrow_mut().push(c);
            }
        }
        self.stack.set_visible_child_name(name);
        self.back_btn.set_visible(!self.history.borrow().is_empty());
        self.on_page_shown(name);
    }

    pub fn back(&self) {
        let prev = self.history.borrow_mut().pop();
        if let Some(n) = prev {
            self.stack.set_visible_child_name(&n);
            self.on_page_shown(&n);
        }
        self.back_btn.set_visible(!self.history.borrow().is_empty());
    }

    fn on_page_shown(&self, name: &str) {
        // Leaving the Shorts feed stops its playback, like the Mac app.
        if name != "shorts" && self.mode.get() == Mode::Shorts {
            self.player.stop();
            self.mode.set(Mode::Idle);
        }
        match name {
            "home" if !self.home_loaded.get() => self.load_home(),
            "shorts" => self.start_shorts(),
            "subs" => self.load_subscriptions(),
            "watch" if self.current.borrow().is_none() => {
                self.watch.title.set_text("Chưa phát video nào");
            }
            _ => {}
        }
    }

    // ------------------------------------------------------------ feeds

    fn load_home(&self) {
        self.home_loaded.set(true);
        self.home.clear();
        let head = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        head.append(&label("Thịnh hành tại Việt Nam", &["title-1"]));
        let refresh = icon_button("view-refresh-symbolic", "Làm mới");
        refresh.add_css_class("flat");
        refresh.connect_clicked(|_| app().load_home());
        head.append(&refresh);
        self.home.header.append(&head);
        self.home.set_loading(true);
        bg(innertube::trending, |p| {
            let a = app();
            if !p.shorts.is_empty() {
                a.home.header.append(&shorts_shelf(&p.shorts));
                a.shorts_seed(&p.shorts);
            }
            if p.videos.is_empty() {
                a.toast("Không tải được trang chủ. Kiểm tra kết nối mạng.");
            }
            a.home.append(&p.videos, None);
        });
    }

    pub fn search(&self, q: &str) {
        let q = q.trim().to_string();
        if q.is_empty() {
            return;
        }
        match innertube::parse_link(&q) {
            Some(Link::Video(id)) => {
                self.open_video(Video { id: id.clone(), thumb: format!("https://i.ytimg.com/vi/{id}/hqdefault.jpg"), ..Default::default() });
                return;
            }
            Some(Link::Channel(c)) => {
                self.open_channel(&c, "");
                return;
            }
            None => {}
        }
        *self.search_query.borrow_mut() = q.clone();
        self.search.clear();
        self.search.header.append(&label(&format!("Kết quả cho “{q}”"), &["title-2"]));
        self.search.set_loading(true);
        self.navigate("search");
        bg(move || innertube::search(&q, None, None), |p| {
            let a = app();
            if !p.shorts.is_empty() {
                a.search.header.append(&shorts_shelf(&p.shorts));
            }
            a.search.append(&p.videos, p.continuation);
        });
    }

    fn load_suggestions(&self, text: &str) {
        let q = text.trim().to_string();
        if q.len() < 2 || q.starts_with("http") {
            self.suggest_pop.popdown();
            return;
        }
        bg(
            {
                let q = q.clone();
                move || innertube::suggestions(&q)
            },
            move |list| {
                let a = app();
                if a.search_entry.text().as_str() != q {
                    return;
                }
                while let Some(c) = a.suggest_list.first_child() {
                    a.suggest_list.remove(&c);
                }
                for s in &list {
                    let l = label(s, &[]);
                    l.set_margin_top(4);
                    l.set_margin_bottom(4);
                    l.set_margin_start(6);
                    a.suggest_list.append(&l);
                }
                if list.is_empty() {
                    a.suggest_pop.popdown();
                } else {
                    a.suggest_pop.set_width_request(a.search_entry.width());
                    a.suggest_pop.popup();
                }
            },
        );
    }

    pub fn open_channel(&self, id_or_handle: &str, name: &str) {
        self.channel.clear();
        *self.channel_info.borrow_mut() = None;
        self.channel.header.append(&label(if name.is_empty() { "Kênh" } else { name }, &["title-1"]));
        self.channel.set_loading(true);
        self.navigate("channel");
        let key = id_or_handle.to_string();
        bg(
            move || {
                let id = innertube::resolve_channel(&key)?;
                innertube::channel(&id, None)
            },
            |r| {
                let a = app();
                let Some((ch, page)) = r else {
                    a.channel.set_loading(false);
                    a.toast("Không tải được kênh");
                    return;
                };
                *a.channel_id.borrow_mut() = ch.id.clone();
                clear_box(&a.channel.header);
                a.channel.header.append(&channel_header(&ch));
                *a.channel_info.borrow_mut() = Some(ch);
                a.channel.append(&page.videos, page.continuation);
            },
        );
    }

    fn load_subscriptions(&self) {
        self.subs.clear();
        let subs = self.settings.borrow().subscriptions.clone();
        self.subs.header.append(&label("Kênh đăng ký", &["title-1"]));
        if subs.is_empty() {
            self.subs.header.append(&label("Bạn chưa đăng ký kênh nào. Mở một kênh và bấm “Đăng ký” để theo dõi video mới.", &["dim-label"]));
            self.subs.append(&[], None);
            return;
        }
        let chips = gtk::FlowBox::new();
        chips.set_selection_mode(gtk::SelectionMode::None);
        chips.set_max_children_per_line(12);
        for c in &subs {
            let b = gtk::Button::with_label(&c.title);
            b.add_css_class("pill");
            let (id, title) = (c.id.clone(), c.title.clone());
            b.connect_clicked(move |_| app().open_channel(&id, &title));
            chips.insert(&b, -1);
        }
        self.subs.header.append(&chips);
        self.subs.set_loading(true);
        bg(
            move || {
                let pages: Vec<Vec<Video>> = std::thread::scope(|s| {
                    let hs: Vec<_> = subs.iter().take(20).map(|c| s.spawn(move || innertube::channel(&c.id, None).map(|(_, p)| p.videos).unwrap_or_default())).collect();
                    hs.into_iter().map(|h| h.join().unwrap_or_default()).collect()
                });
                let mut out = vec![];
                for i in 0..8 {
                    for p in &pages {
                        if let Some(v) = p.get(i) {
                            out.push(v.clone());
                        }
                    }
                }
                out
            },
            |videos| app().subs.append(&videos, None),
        );
    }

    pub fn toggle_subscription(&self, ch: Channel) -> bool {
        let now = self.settings.borrow_mut().toggle_subscription(ch.clone());
        self.settings.borrow().save();
        self.toast(&if now { format!("Đã đăng ký {}", ch.title) } else { format!("Đã hủy đăng ký {}", ch.title) });
        now
    }

    // ------------------------------------------------------------ playback

    fn effective_quality(&self) -> String {
        let q = self.settings.borrow().quality.clone();
        if q == "auto" {
            self.auto_quality.borrow().clone()
        } else {
            q
        }
    }

    fn views(&self) -> [&Rc<PlayerView>; 2] {
        [&self.watch.view, &self.shorts.view]
    }

    fn play_stream(&self, v: &Video, quality: &str, start: f64) {
        let token = self.token.get() + 1;
        self.token.set(token);
        self.player.stop();
        self.segments.borrow_mut().clear();
        for view in self.views() {
            view.set_loading(true);
        }
        let (id, q) = (v.id.clone(), quality.to_string());
        bg(move || ytdlp::stream_urls(&id, &q), move |res| {
            let a = app();
            if a.token.get() != token {
                return;
            }
            match res {
                Ok((video, audio)) => a.player.load(&video, audio.as_deref(), start),
                Err(e) => a.views().iter().for_each(|view| view.set_error(&e)),
            }
        });
        if self.settings.borrow().sponsorblock && !v.is_short {
            let id = v.id.clone();
            bg(move || sponsorblock::fetch(&id), move |segs| {
                let a = app();
                if a.token.get() == token {
                    *a.segments.borrow_mut() = segs;
                }
            });
        }
        self.update_media_metadata(v);
    }

    pub fn open_video(&self, v: Video) {
        self.mode.set(Mode::Watch);
        *self.current.borrow_mut() = Some(v.clone());
        *self.current_details.borrow_mut() = None;
        self.show_watch_basic(&v);
        self.navigate("watch");
        let q = self.effective_quality();
        self.watch.view.set_quality(&self.settings.borrow().quality);
        self.play_stream(&v, &q, 0.0);
        let id = v.id.clone();
        bg(move || innertube::details(&id), move |d| {
            let a = app();
            let Some(d) = d else { return };
            if a.current.borrow().as_ref().map(|c| c.id != v.id).unwrap_or(true) {
                return;
            }
            a.show_watch_details(&d);
            if let Some(cur) = a.current.borrow_mut().as_mut() {
                if cur.title.is_empty() {
                    cur.title = d.title.clone();
                }
                if cur.channel.is_empty() {
                    cur.channel = d.channel.clone();
                }
                cur.channel_id = d.channel_id.clone().or(cur.channel_id.take());
            }
            if let Some(cur) = a.current.borrow().clone() {
                a.update_media_metadata(&cur);
            }
            *a.related.borrow_mut() = d.related.clone();
            *a.current_details.borrow_mut() = Some(d);
        });
    }

    pub fn change_quality(&self, q: &str) {
        {
            let mut s = self.settings.borrow_mut();
            s.quality = q.into();
            s.save();
        }
        if self.mode.get() != Mode::Watch {
            return;
        }
        let Some(v) = self.current.borrow().clone() else { return };
        let pos = self.player.position();
        let eq = self.effective_quality();
        self.toast(&format!("Đổi chất lượng: {}", if q == "auto" { format!("Tự động ({eq}p)") } else { format!("{q}p") }));
        self.play_stream(&v, &eq, pos);
    }

    pub fn set_volume(&self, v: f64) {
        self.player.set_volume(v);
        let mut s = self.settings.borrow_mut();
        s.volume = v;
        s.save();
    }

    fn on_player_event(&self, e: Event) {
        match e {
            Event::Ready => self.views().iter().for_each(|v| v.set_loading(false)),
            Event::Error(msg) => self.views().iter().for_each(|v| v.set_error(&msg)),
            Event::Eos => match self.mode.get() {
                Mode::Shorts => {
                    self.player.seek(0.0);
                    self.player.play();
                }
                Mode::Watch => {
                    let next = self.related.borrow().first().cloned();
                    if let (true, Some(n)) = (self.settings.borrow().autoplay, next) {
                        self.toast(&format!("Đang phát tiếp: {}", n.title));
                        glib::idle_add_local_once(move || app().open_video(n));
                    }
                }
                Mode::Idle => {}
            },
        }
    }

    fn tick(&self) {
        if !self.player.has_media() {
            return;
        }
        let (pos, dur, playing) = (self.player.position(), self.player.duration(), self.player.is_playing());
        for v in self.views() {
            v.update(pos, dur, playing);
        }
        let skip = self.segments.borrow().iter().find(|s| pos >= s.start && pos < s.end - 0.5).cloned();
        if let Some(s) = skip {
            self.player.seek(s.end);
            self.toast(&format!("Đã bỏ qua {}", sponsorblock::label(&s.category)));
        }
        if self.last_playing.get() != Some(playing) {
            self.last_playing.set(Some(playing));
            if let Some(m) = self.media.borrow_mut().as_mut() {
                let progress = Some(souvlaki::MediaPosition(Duration::from_secs_f64(pos)));
                let _ = m.set_playback(if playing { souvlaki::MediaPlayback::Playing { progress } } else { souvlaki::MediaPlayback::Paused { progress } });
            }
        }
    }

    pub fn handle(&self, c: Cmd) {
        match c {
            Cmd::Show => {
                self.window.set_visible(true);
                self.window.present();
            }
            Cmd::Play => self.player.play(),
            Cmd::Pause => self.player.pause(),
            Cmd::Toggle => self.player.toggle(),
            Cmd::Seek(s) => self.player.seek(s),
            Cmd::Next => self.next(),
            Cmd::Prev => self.prev(),
            Cmd::Quit => {
                self.player.stop();
                self.gapp.quit();
            }
        }
    }

    fn next(&self) {
        match self.mode.get() {
            Mode::Shorts => self.shorts_step(1),
            _ => {
                let n = self.related.borrow().first().cloned();
                if let Some(n) = n {
                    self.open_video(n);
                }
            }
        }
    }

    fn prev(&self) {
        match self.mode.get() {
            Mode::Shorts => self.shorts_step(-1),
            _ => self.player.seek(0.0),
        }
    }

    // ------------------------------------------------------------ watch page

    fn show_watch_basic(&self, v: &Video) {
        let w = &self.watch;
        w.title.set_text(&v.title);
        w.channel_btn.set_label(if v.channel.is_empty() { "…" } else { &v.channel });
        w.meta.set_text(&[v.views.as_str(), v.published.as_str()].iter().filter(|s| !s.is_empty()).cloned().collect::<Vec<_>>().join(" • "));
        w.desc.set_text("");
        w.subs.set_text("");
        w.avatar.set_paintable(None::<&gtk::gdk::Paintable>);
        self.update_sub_button(v.channel_id.as_deref());
        clear_box(&w.related);
        let sp = gtk::Spinner::new();
        sp.set_spinning(true);
        sp.set_margin_top(24);
        w.related.append(&sp);
        self.related.borrow_mut().clear();
    }

    fn show_watch_details(&self, d: &Details) {
        let w = &self.watch;
        if !d.title.is_empty() {
            w.title.set_text(&d.title);
        }
        if !d.channel.is_empty() {
            w.channel_btn.set_label(&d.channel);
        }
        w.subs.set_text(&d.subs);
        load_image(&w.avatar, &d.channel_avatar);
        let meta = [d.views.as_str(), d.date.as_str()].iter().filter(|s| !s.is_empty()).cloned().collect::<Vec<_>>().join(" • ");
        if !meta.is_empty() {
            w.meta.set_text(&meta);
        }
        w.desc.set_text(&d.description);
        self.update_sub_button(d.channel_id.as_deref());
        clear_box(&w.related);
        w.related.append(&label("Video liên quan", &["title-4"]));
        for v in d.related.iter().take(30) {
            w.related.append(&related_row(v));
        }
    }

    fn update_sub_button(&self, channel_id: Option<&str>) {
        let b = &self.watch.sub_btn;
        match channel_id {
            Some(id) => {
                b.set_visible(true);
                let subbed = self.settings.borrow().is_subscribed(id);
                b.set_label(if subbed { "Đã đăng ký" } else { "Đăng ký" });
                if subbed {
                    b.remove_css_class("suggested-action");
                } else {
                    b.add_css_class("suggested-action");
                }
            }
            None => b.set_visible(false),
        }
    }

    fn watch_channel(&self) -> Option<Channel> {
        let cur = self.current.borrow().clone()?;
        let d = self.current_details.borrow().clone();
        Some(Channel {
            id: cur.channel_id.clone()?,
            title: d.as_ref().map(|d| d.channel.clone()).filter(|s| !s.is_empty()).unwrap_or(cur.channel),
            avatar: d.as_ref().map(|d| d.channel_avatar.clone()).unwrap_or_default(),
            subs: d.map(|d| d.subs).unwrap_or_default(),
        })
    }

    pub fn download_current(&self, kind: Kind) {
        let Some(v) = self.current.borrow().clone() else { return };
        let (dir, q) = {
            let s = self.settings.borrow();
            (s.download_dir.clone(), s.download_quality.clone())
        };
        self.downloads.start(&v, kind, &dir, &q);
        self.toast(&format!("Đang tải xuống: {}", v.title));
    }

    // ------------------------------------------------------------ shorts

    fn shorts_seed(&self, list: &[Video]) {
        let mut items = self.shorts.items.borrow_mut();
        for v in list {
            if !items.iter().any(|x| x.id == v.id) {
                items.push(v.clone());
            }
        }
    }

    pub fn open_short(&self, v: Video) {
        {
            let mut items = self.shorts.items.borrow_mut();
            items.retain(|x| x.id != v.id);
            let idx = self.shorts.idx.get().min(items.len());
            items.insert(idx, v);
        }
        self.navigate("shorts");
        self.play_short();
    }

    fn start_shorts(&self) {
        if self.mode.get() == Mode::Shorts && self.player.has_media() {
            return;
        }
        if self.shorts.items.borrow().is_empty() {
            self.load_more_shorts(true);
        } else {
            self.play_short();
        }
    }

    fn load_more_shorts(&self, play: bool) {
        if self.shorts.loading.replace(true) {
            return;
        }
        self.shorts.view.set_loading(true);
        let cont = self.shorts.cont.borrow().clone();
        bg(move || innertube::shorts_feed(cont.as_deref()), move |p| {
            let a = app();
            a.shorts.loading.set(false);
            *a.shorts.cont.borrow_mut() = p.continuation;
            a.shorts_seed(&p.shorts);
            if play {
                a.play_short();
            }
        });
    }

    fn play_short(&self) {
        let v = self.shorts.items.borrow().get(self.shorts.idx.get()).cloned();
        let Some(v) = v else {
            self.shorts.view.set_error("Không tải được Shorts");
            return;
        };
        self.mode.set(Mode::Shorts);
        *self.current.borrow_mut() = Some(v.clone());
        self.related.borrow_mut().clear();
        self.shorts.title.set_text(&v.title);
        self.shorts.meta.set_text(&v.views);
        self.play_stream(&v, "shorts", 0.0);
        if self.shorts.idx.get() + 3 >= self.shorts.items.borrow().len() {
            self.load_more_shorts(false);
        }
    }

    pub fn shorts_step(&self, delta: i32) {
        let len = self.shorts.items.borrow().len() as i32;
        let idx = (self.shorts.idx.get() as i32 + delta).clamp(0, (len - 1).max(0));
        if idx as usize == self.shorts.idx.get() {
            return;
        }
        self.shorts.idx.set(idx as usize);
        self.play_short();
    }

    // ------------------------------------------------------------ window modes

    pub fn toggle_fullscreen(&self) {
        if self.window.is_fullscreen() {
            self.window.unfullscreen();
        } else {
            self.window.fullscreen();
        }
    }

    fn on_fullscreen(&self, full: bool) {
        for w in [self.header.upcast_ref::<gtk::Widget>(), self.sidebar.upcast_ref(), self.watch.details.upcast_ref(), self.watch.side.upcast_ref(), self.shorts_side().upcast_ref()] {
            w.set_visible(!full);
        }
        if let Some(sep) = self.sidebar.next_sibling() {
            sep.set_visible(!full);
        }
    }

    fn shorts_side(&self) -> gtk::Widget {
        self.shorts.root.last_child().unwrap_or_else(|| self.shorts.root.clone().upcast())
    }

    /// Mini player window (port of MiniNativePlayerView / PiPWindowController).
    /// GTK4 has no portable always-on-top; on X11 we ask the WM via wmctrl when present.
    pub fn toggle_mini(&self) {
        if let Some(w) = self.mini.borrow_mut().take() {
            w.close();
            return;
        }
        let win = gtk::Window::new();
        let title = "AuraTube — Trình phát mini";
        win.set_title(Some(title));
        win.set_default_size(480, 270);
        win.set_icon_name(Some("auratube"));
        let pic = gtk::Picture::new();
        pic.set_can_shrink(true);
        let bgbox = gtk::Box::new(gtk::Orientation::Vertical, 0);
        bgbox.add_css_class("player-bg");
        pic.set_vexpand(true);
        bgbox.append(&pic);
        let ov = gtk::Overlay::new();
        ov.set_child(Some(&bgbox));
        let bar = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        bar.add_css_class("player-controls");
        bar.set_valign(gtk::Align::End);
        let play = gtk::Button::from_icon_name("media-playback-start-symbolic");
        play.add_css_class("flat");
        play.connect_clicked(|_| app().player.toggle());
        let back = gtk::Button::from_icon_name("view-fullscreen-symbolic");
        back.add_css_class("flat");
        back.set_tooltip_text(Some("Quay lại cửa sổ chính"));
        back.connect_clicked(|_| {
            let a = app();
            a.toggle_mini();
            a.handle(Cmd::Show);
        });
        let sp = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        sp.set_hexpand(true);
        bar.append(&play);
        bar.append(&sp);
        bar.append(&back);
        ov.add_overlay(&bar);
        win.set_child(Some(&ov));
        self.player.add_picture(&pic);
        let p2 = pic.clone();
        win.connect_close_request(move |_| {
            let a = app();
            a.player.remove_picture(&p2);
            a.mini.borrow_mut().take();
            glib::Propagation::Proceed
        });
        let play_w = play.downgrade();
        glib::timeout_add_local(Duration::from_millis(400), move || {
            let Some(p) = play_w.upgrade() else { return glib::ControlFlow::Break };
            p.set_icon_name(if app().player.is_playing() { "media-playback-pause-symbolic" } else { "media-playback-start-symbolic" });
            glib::ControlFlow::Continue
        });
        win.present();
        self.window.minimize();
        if let Some(wm) = which("wmctrl") {
            glib::timeout_add_local_once(Duration::from_millis(500), move || {
                let _ = std::process::Command::new(wm).args(["-r", title, "-b", "add,above"]).spawn();
            });
        }
        *self.mini.borrow_mut() = Some(win);
    }

    // ------------------------------------------------------------ system integration

    fn setup_actions(&self) {
        let add = |name: &str, f: fn()| {
            let act = gio::SimpleAction::new(name, None);
            act.connect_activate(move |_, _| f());
            self.gapp.add_action(&act);
        };
        add("about", || app().show_about());
        add("check-update", || app().check_update(true));
        add("releases", || open_uri(update::RELEASES));
        add("quit", || app().handle(Cmd::Quit));
        self.gapp.set_accels_for_action("app.quit", &["<Control>q"]);
    }

    fn setup_keys(&self) {
        let keys = gtk::EventControllerKey::new();
        keys.set_propagation_phase(gtk::PropagationPhase::Capture);
        keys.connect_key_pressed(|_, key, _, _| {
            use gtk::gdk::Key;
            let a = app();
            if gtk::prelude::GtkWindowExt::focus(&a.window).map(|w| w.is::<gtk::Text>()).unwrap_or(false) {
                if key == Key::Escape {
                    a.suggest_pop.popdown();
                }
                return glib::Propagation::Proceed;
            }
            let page = a.stack.visible_child_name().map(|s| s.to_string()).unwrap_or_default();
            if page != "watch" && page != "shorts" {
                return glib::Propagation::Proceed;
            }
            match key {
                Key::space | Key::k => a.player.toggle(),
                Key::f => a.toggle_fullscreen(),
                Key::Escape if a.window.is_fullscreen() => a.window.unfullscreen(),
                Key::Left => a.player.seek_by(-5.0),
                Key::Right => a.player.seek_by(5.0),
                Key::j => a.player.seek_by(-10.0),
                Key::l => a.player.seek_by(10.0),
                Key::Up if page == "shorts" => a.shorts_step(-1),
                Key::Down if page == "shorts" => a.shorts_step(1),
                Key::Up => a.set_volume((a.player.volume() + 0.1).min(1.0)),
                Key::Down => a.set_volume((a.player.volume() - 0.1).max(0.0)),
                Key::m => a.set_volume(if a.player.volume() > 0.0 { 0.0 } else { 1.0 }),
                _ => return glib::Propagation::Proceed,
            }
            glib::Propagation::Stop
        });
        self.window.add_controller(keys);
    }

    fn setup_media_controls(&self) {
        let (tx, rx) = async_channel::unbounded::<Cmd>();
        let config = souvlaki::PlatformConfig { dbus_name: "auratube", display_name: "AuraTube", hwnd: None };
        if let Ok(mut mc) = souvlaki::MediaControls::new(config) {
            let t = tx.clone();
            let attached = mc.attach(move |e: souvlaki::MediaControlEvent| {
                use souvlaki::MediaControlEvent as E;
                let cmd = match e {
                    E::Play => Cmd::Play,
                    E::Pause => Cmd::Pause,
                    E::Toggle => Cmd::Toggle,
                    E::Next => Cmd::Next,
                    E::Previous => Cmd::Prev,
                    E::Raise => Cmd::Show,
                    E::Quit => Cmd::Quit,
                    E::SetPosition(souvlaki::MediaPosition(d)) => Cmd::Seek(d.as_secs_f64()),
                    _ => return,
                };
                let _ = t.send_blocking(cmd);
            });
            if attached.is_ok() {
                *self.media.borrow_mut() = Some(mc);
            }
        }
        crate::tray::spawn(tx);
        glib::spawn_future_local(async move {
            while let Ok(c) = rx.recv().await {
                app().handle(c);
            }
        });
    }

    fn update_media_metadata(&self, v: &Video) {
        self.last_playing.set(None);
        if let Some(m) = self.media.borrow_mut().as_mut() {
            let _ = m.set_metadata(souvlaki::MediaMetadata {
                title: Some(&v.title),
                artist: Some(&v.channel),
                album: None,
                cover_url: Some(&v.thumb),
                duration: None,
            });
        }
    }

    fn show_about(&self) {
        let d = gtk::AboutDialog::builder()
            .program_name("AuraTube")
            .version(env!("CARGO_PKG_VERSION"))
            .logo_icon_name("auratube")
            .comments(format!("Xem YouTube không quảng cáo.\nyt-dlp: {}", ytdlp::version().unwrap_or_else(|| "chưa cài".into())))
            .website("https://github.com/tung68nt/AuraTube")
            .license_type(gtk::License::MitX11)
            .transient_for(&self.window)
            .modal(true)
            .build();
        d.present();
    }

    pub fn check_update(&self, manual: bool) {
        bg(update::check, move |r| {
            let a = app();
            match r {
                Some(u) => {
                    a.update_label.set_text(&format!("Đã có {} — bạn đang dùng v{}", u.title, env!("CARGO_PKG_VERSION")));
                    a.update_label.set_tooltip_text(Some(&u.notes));
                    *a.update_url.borrow_mut() = u.url;
                    a.update_bar.set_reveal_child(true);
                }
                None if manual => a.toast("Bạn đang dùng phiên bản mới nhất"),
                None => {}
            }
        });
    }
}

// ---------------------------------------------------------------- page builders

fn channel_header(ch: &Channel) -> gtk::Widget {
    let b = gtk::Box::new(gtk::Orientation::Horizontal, 16);
    b.set_margin_bottom(12);
    let pic = gtk::Picture::new();
    pic.set_size_request(88, 88);
    pic.add_css_class("avatar");
    pic.set_overflow(gtk::Overflow::Hidden);
    load_image(&pic, &ch.avatar);
    let info = gtk::Box::new(gtk::Orientation::Vertical, 4);
    info.set_valign(gtk::Align::Center);
    info.append(&label(&ch.title, &["title-1"]));
    if !ch.subs.is_empty() {
        info.append(&label(&ch.subs, &["dim-label"]));
    }
    let btn = gtk::Button::new();
    btn.set_valign(gtk::Align::Center);
    let set = |b: &gtk::Button, s: bool| {
        b.set_label(if s { "Đã đăng ký" } else { "Đăng ký" });
        if s {
            b.remove_css_class("suggested-action")
        } else {
            b.add_css_class("suggested-action")
        }
    };
    set(&btn, app().settings.borrow().is_subscribed(&ch.id));
    let c = ch.clone();
    btn.connect_clicked(move |b| set(b, app().toggle_subscription(c.clone())));
    b.append(&pic);
    b.append(&info);
    b.append(&btn);
    b.upcast()
}

fn related_row(v: &Video) -> gtk::Widget {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 10);
    row.set_cursor_from_name(Some("pointer"));
    let pic = gtk::Picture::new();
    pic.set_size_request(168, 94);
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
        d.set_margin_end(4);
        d.set_margin_bottom(4);
        ov.add_overlay(&d);
    }
    let info = gtk::Box::new(gtk::Orientation::Vertical, 2);
    info.set_hexpand(true);
    let t = label(&v.title, &["video-title"]);
    t.set_wrap(true);
    t.set_wrap_mode(pango::WrapMode::WordChar);
    t.set_lines(2);
    t.set_ellipsize(pango::EllipsizeMode::End);
    t.set_max_width_chars(24);
    info.append(&t);
    let c = label(&v.channel, &["dim-label", "caption"]);
    c.set_ellipsize(pango::EllipsizeMode::End);
    info.append(&c);
    let m = label(&v.views, &["dim-label", "caption"]);
    m.set_ellipsize(pango::EllipsizeMode::End);
    info.append(&m);
    row.append(&ov);
    row.append(&info);
    let click = gtk::GestureClick::new();
    let video = v.clone();
    click.connect_released(move |_, _, _, _| app().open_video(video.clone()));
    row.add_controller(click);
    row.upcast()
}

fn build_watch_page() -> WatchPage {
    let view = PlayerView::new(false);
    let frame = gtk::AspectFrame::new(0.5, 0.0, 16.0 / 9.0, false);
    frame.set_child(Some(&view.root));
    frame.set_size_request(480, 270);

    let details = gtk::Box::new(gtk::Orientation::Vertical, 10);
    let title = label("", &["title-2"]);
    title.set_wrap(true);
    title.set_selectable(true);
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 10);
    let avatar = gtk::Picture::new();
    avatar.set_size_request(40, 40);
    avatar.add_css_class("avatar");
    avatar.set_overflow(gtk::Overflow::Hidden);
    let chbox = gtk::Box::new(gtk::Orientation::Vertical, 0);
    let channel_btn = gtk::Button::with_label("");
    channel_btn.add_css_class("flat");
    channel_btn.add_css_class("heading");
    channel_btn.set_halign(gtk::Align::Start);
    let subs = label("", &["dim-label", "caption"]);
    subs.set_margin_start(10);
    chbox.append(&channel_btn);
    chbox.append(&subs);
    let sub_btn = gtk::Button::with_label("Đăng ký");
    sub_btn.set_valign(gtk::Align::Center);
    let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    spacer.set_hexpand(true);
    let mp4 = gtk::Button::with_label("Tải MP4");
    let mp3 = gtk::Button::with_label("Tải MP3");
    let ext = icon_button("web-browser-symbolic", "Mở trên YouTube");
    for b in [&mp4, &mp3, &ext] {
        b.set_valign(gtk::Align::Center);
    }
    row.append(&avatar);
    row.append(&chbox);
    row.append(&sub_btn);
    row.append(&spacer);
    row.append(&mp4);
    row.append(&mp3);
    row.append(&ext);
    let meta = label("", &["dim-label"]);
    let desc = label("", &[]);
    desc.set_wrap(true);
    desc.set_wrap_mode(pango::WrapMode::WordChar);
    desc.set_selectable(true);
    let expander = gtk::Expander::new(Some("Mô tả"));
    expander.set_child(Some(&desc));
    details.append(&title);
    details.append(&row);
    details.append(&meta);
    details.append(&expander);

    let left = gtk::Box::new(gtk::Orientation::Vertical, 14);
    left.set_margin_top(16);
    left.set_margin_start(20);
    left.set_margin_end(12);
    left.set_margin_bottom(20);
    left.append(&frame);
    left.append(&details);
    let left_sc = gtk::ScrolledWindow::new();
    left_sc.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    left_sc.set_child(Some(&left));
    left_sc.set_hexpand(true);

    let related = gtk::Box::new(gtk::Orientation::Vertical, 10);
    related.set_margin_top(16);
    related.set_margin_end(16);
    related.set_margin_start(6);
    related.set_margin_bottom(16);
    let side = gtk::ScrolledWindow::new();
    side.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    side.set_width_request(400);
    side.set_child(Some(&related));

    let root = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    root.append(&left_sc);
    root.append(&side);

    channel_btn.connect_clicked(|b| {
        let a = app();
        let id = a.current.borrow().as_ref().and_then(|v| v.channel_id.clone());
        if let Some(id) = id {
            a.open_channel(&id, &b.label().map(|s| s.to_string()).unwrap_or_default());
        }
    });
    sub_btn.connect_clicked(|_| {
        let a = app();
        if let Some(ch) = a.watch_channel() {
            let id = ch.id.clone();
            a.toggle_subscription(ch);
            a.update_sub_button(Some(&id));
        }
    });
    mp4.connect_clicked(|_| app().download_current(Kind::Mp4));
    mp3.connect_clicked(|_| app().download_current(Kind::Mp3));
    ext.connect_clicked(|_| {
        if let Some(v) = app().current.borrow().as_ref() {
            open_uri(&format!("https://www.youtube.com/watch?v={}", v.id));
        }
    });

    WatchPage { root, view, details, side, title, channel_btn, avatar, subs, sub_btn, meta, desc, related }
}

fn build_shorts_page() -> ShortsPage {
    let view = PlayerView::new(true);
    let frame = gtk::AspectFrame::new(0.5, 0.5, 9.0 / 16.0, false);
    frame.set_child(Some(&view.root));
    frame.set_hexpand(true);
    frame.set_vexpand(true);
    frame.set_margin_top(12);
    frame.set_margin_bottom(12);

    let side = gtk::Box::new(gtk::Orientation::Vertical, 12);
    side.set_valign(gtk::Align::Center);
    side.set_margin_end(24);
    side.set_width_request(260);
    let up = icon_button("go-up-symbolic", "Short trước (↑)");
    let down = icon_button("go-down-symbolic", "Short tiếp theo (↓)");
    for b in [&up, &down] {
        b.add_css_class("circular");
        b.set_halign(gtk::Align::Start);
    }
    let title = label("", &["title-4"]);
    title.set_wrap(true);
    title.set_max_width_chars(28);
    let meta = label("", &["dim-label"]);
    side.append(&up);
    side.append(&title);
    side.append(&meta);
    side.append(&down);
    up.connect_clicked(|_| app().shorts_step(-1));
    down.connect_clicked(|_| app().shorts_step(1));

    let root = gtk::Box::new(gtk::Orientation::Horizontal, 16);
    root.append(&frame);
    root.append(&side);

    let scroll = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::VERTICAL);
    scroll.connect_scroll(|_, _, dy| {
        let a = app();
        let now = Instant::now();
        if a.shorts.last_scroll.get().map(|t| now.duration_since(t) < Duration::from_millis(600)).unwrap_or(false) || dy.abs() < 0.5 {
            return glib::Propagation::Stop;
        }
        a.shorts.last_scroll.set(Some(now));
        a.shorts_step(if dy > 0.0 { 1 } else { -1 });
        glib::Propagation::Stop
    });
    root.add_controller(scroll);

    ShortsPage {
        root,
        view,
        title,
        meta,
        items: RefCell::new(vec![]),
        idx: Cell::new(0),
        cont: RefCell::new(None),
        loading: Cell::new(false),
        last_scroll: Cell::new(None),
    }
}

fn switch_row(title: &str, subtitle: &str, value: bool, f: impl Fn(&mut Settings, bool) + 'static) -> adw::ActionRow {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_subtitle(subtitle);
    let sw = gtk::Switch::new();
    sw.set_active(value);
    sw.set_valign(gtk::Align::Center);
    sw.connect_active_notify(move |s| {
        let a = app();
        let mut st = a.settings.borrow_mut();
        f(&mut st, s.is_active());
        st.save();
    });
    row.add_suffix(&sw);
    row.set_activatable_widget(Some(&sw));
    row
}

fn build_settings_page() -> gtk::Widget {
    let s = app().settings.borrow().clone();
    let page = adw::PreferencesPage::new();

    let play = adw::PreferencesGroup::new();
    play.set_title("Phát video");
    let q = adw::ComboRow::new();
    q.set_title("Chất lượng mặc định");
    q.set_subtitle("“Tự động” chọn theo tốc độ mạng");
    q.set_model(Some(&gtk::StringList::new(&crate::widgets::QUALITY_LABELS)));
    q.set_selected(QUALITIES.iter().position(|x| *x == s.quality).unwrap_or(0) as u32);
    q.connect_selected_notify(|r| {
        let a = app();
        let mut st = a.settings.borrow_mut();
        st.quality = QUALITIES[r.selected() as usize % QUALITIES.len()].into();
        st.save();
    });
    play.add(&q);
    play.add(&switch_row("Tự động phát video tiếp theo", "Phát video liên quan khi video hiện tại kết thúc", s.autoplay, |s, v| s.autoplay = v));
    play.add(&switch_row("Bỏ qua quảng cáo trong video (SponsorBlock)", "Tự động bỏ qua đoạn tài trợ, mở đầu, kết thúc…", s.sponsorblock, |s, v| s.sponsorblock = v));
    page.add(&play);

    let dl = adw::PreferencesGroup::new();
    dl.set_title("Tải xuống");
    let folder = adw::ActionRow::new();
    folder.set_title("Thư mục lưu");
    folder.set_subtitle(&s.download_dir);
    let choose = gtk::Button::with_label("Chọn…");
    choose.set_valign(gtk::Align::Center);
    let fr = folder.clone();
    choose.connect_clicked(move |_| {
        let a = app();
        let dialog = gtk::FileChooserNative::new(Some("Chọn thư mục tải xuống"), Some(&a.window), gtk::FileChooserAction::SelectFolder, Some("Chọn"), Some("Hủy"));
        let fr = fr.clone();
        dialog.connect_response(move |d, resp| {
            if resp == gtk::ResponseType::Accept {
                if let Some(path) = d.file().and_then(|f| f.path()) {
                    let p = path.to_string_lossy().to_string();
                    fr.set_subtitle(&p);
                    let a = app();
                    let mut st = a.settings.borrow_mut();
                    st.download_dir = p;
                    st.save();
                }
            }
        });
        dialog.show();
        // Keep the native dialog alive until it responds.
        unsafe { dialog.set_data("keep", dialog.clone()) };
    });
    folder.add_suffix(&choose);
    dl.add(&folder);
    let dq_vals = ["1080", "720", "480", "360"];
    let dq = adw::ComboRow::new();
    dq.set_title("Chất lượng MP4");
    dq.set_model(Some(&gtk::StringList::new(&["1080p", "720p", "480p", "360p"])));
    dq.set_selected(dq_vals.iter().position(|x| *x == s.download_quality).unwrap_or(0) as u32);
    dq.connect_selected_notify(move |r| {
        let a = app();
        let mut st = a.settings.borrow_mut();
        st.download_quality = dq_vals[r.selected() as usize % dq_vals.len()].into();
        st.save();
    });
    dl.add(&dq);
    let ff = adw::ActionRow::new();
    ff.set_title("ffmpeg");
    ff.set_subtitle(if ytdlp::ffmpeg_dir().is_some() { "Đã cài — tải MP4 chất lượng cao và MP3" } else { "Chưa cài — vẫn tải được MP4 (một tệp) và âm thanh M4A. Cài bằng: sudo apt install ffmpeg" });
    dl.add(&ff);
    page.add(&dl);

    let appg = adw::PreferencesGroup::new();
    appg.set_title("Ứng dụng");
    appg.add(&switch_row("Chạy nền khi đóng cửa sổ", "Tiếp tục phát nhạc; mở lại từ biểu tượng khay hệ thống", s.run_in_background, |s, v| s.run_in_background = v));
    let yt = adw::ActionRow::new();
    yt.set_title("yt-dlp");
    yt.set_subtitle("Đang kiểm tra…");
    let ytb = gtk::Button::with_label("Cập nhật");
    ytb.set_valign(gtk::Align::Center);
    let ytr = yt.clone();
    bg(ytdlp::version, move |v| ytr.set_subtitle(&v.map(|v| format!("Phiên bản {v}")).unwrap_or_else(|| "Chưa cài — sẽ tự tải khi cần".into())));
    let ytr = yt.clone();
    ytb.connect_clicked(move |b| {
        b.set_sensitive(false);
        ytr.set_subtitle("Đang tải bản mới nhất…");
        let (ytr, b) = (ytr.clone(), b.clone());
        bg(
            || ytdlp::install(true).map(|_| ytdlp::version().unwrap_or_default()),
            move |r| {
                b.set_sensitive(true);
                ytr.set_subtitle(&match r {
                    Ok(v) => format!("Phiên bản {v}"),
                    Err(e) => format!("Lỗi: {e}"),
                });
            },
        );
    });
    yt.add_suffix(&ytb);
    appg.add(&yt);
    let ver = adw::ActionRow::new();
    ver.set_title("Phiên bản AuraTube");
    ver.set_subtitle(env!("CARGO_PKG_VERSION"));
    let chk = gtk::Button::with_label("Kiểm tra cập nhật");
    chk.set_valign(gtk::Align::Center);
    chk.connect_clicked(|_| app().check_update(true));
    ver.add_suffix(&chk);
    appg.add(&ver);
    page.add(&appg);
    page.upcast()
}
