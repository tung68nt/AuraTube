//! StatusNotifier tray icon (port of MenuBarController.swift's menu).

use crate::app::Cmd;
use async_channel::Sender;

struct Tray {
    tx: Sender<Cmd>,
}

impl Tray {
    fn send(&self, c: Cmd) {
        let _ = self.tx.send_blocking(c);
    }
}

impl ksni::Tray for Tray {
    fn id(&self) -> String {
        "auratube".into()
    }
    fn title(&self) -> String {
        "AuraTube".into()
    }
    fn icon_name(&self) -> String {
        "auratube".into()
    }
    fn activate(&mut self, _x: i32, _y: i32) {
        self.send(Cmd::Show);
    }
    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        use ksni::menu::StandardItem;
        let item = |label: &str, f: fn(&mut Self)| -> ksni::MenuItem<Self> {
            StandardItem { label: label.into(), activate: Box::new(f), ..Default::default() }.into()
        };
        vec![
            item("Mở AuraTube", |t| t.send(Cmd::Show)),
            item("Phát / Tạm dừng", |t| t.send(Cmd::Toggle)),
            item("Video tiếp theo", |t| t.send(Cmd::Next)),
            ksni::MenuItem::Separator,
            item("Thoát", |t| t.send(Cmd::Quit)),
        ]
    }
}

/// Starts the tray service on its own thread. Desktops without a StatusNotifier host
/// (stock GNOME without the AppIndicator extension) simply show nothing.
pub fn spawn(tx: Sender<Cmd>) {
    let service = ksni::TrayService::new(Tray { tx });
    service.spawn();
}
