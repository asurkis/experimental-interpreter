mod interpreter;
mod parser;

use interpreter::parse_interpret;

#[derive(Debug, Clone, Default)]
struct MyApp {
    text_input: String,
    input_changed: bool,
    last_out: String,
    last_err: String,
    last_ok: bool,
}

impl MyApp {
    fn new() -> Self {
        Self {
            text_input: "(+ 1 1)".into(),
            input_changed: true,
            last_out: "".into(),
            last_err: "".into(),
            last_ok: false,
        }
    }
}

impl eframe::App for MyApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::Window::new("Input").show(ctx, |ui| {
            self.input_changed |= ui.code_editor(&mut self.text_input).changed();
        });
        if self.input_changed {
            match parse_interpret(&self.text_input) {
                Ok(val) => {
                    self.last_out = format!("{val:?}");
                    self.last_err.clear();
                    self.last_ok = true;
                }
                Err(err) => {
                    self.last_err = err;
                    self.last_ok = false;
                }
            }
        }
        egui::Window::new("Output").show(ctx, |ui| {
            ui.label(
                egui::RichText::new(&self.last_out)
                    .monospace()
                    .color(if self.last_ok {
                        egui::Color32::DARK_GREEN
                    } else {
                        egui::Color32::from_rgb(128, 128, 0)
                    }),
            );
            ui.label(
                egui::RichText::new(&self.last_err)
                    .monospace()
                    .color(egui::Color32::RED),
            );
        });
    }
}

fn main() -> eframe::Result {
    eframe::run_native(
        "App1",
        eframe::NativeOptions {
            centered: true,
            ..Default::default()
        },
        Box::new(|_| Ok(Box::new(MyApp::new()))),
    )
}
