mod app_state;
mod fbo;
mod file;
mod image_loading;
mod image_pool;
mod lut_lib;
mod setup;
mod shader;
mod shader_lib;
mod texture;

use std::path::PathBuf;

use anyhow::Context;
use app_state::*;
use glutin::event::{Event, WindowEvent};
use glutin::event_loop::{ControlFlow, EventLoop};
use glutin::window::WindowBuilder;
use glutin::ContextBuilder;

use structopt::StructOpt;

#[derive(StructOpt)]
#[structopt(name = "notorious6", about = "HDR display mapping stuffs.")]
struct Opt {
    #[structopt(
        parse(from_os_str),
        default_value = "img",
        help = "A single file or a folder containing .exr or .hdr images"
    )]
    input: PathBuf,

    #[structopt(subcommand)]
    cmd: Option<Command>,
}

#[derive(StructOpt)]
#[structopt(settings = &[structopt::clap::AppSettings::AllowNegativeNumbers])]
struct BatchCmd {
    /// Name of the shader, without the path or file extension, e.g. "linear"
    #[structopt(long)]
    shader: String,

    /// Min EV
    #[structopt(long)]
    ev_min: f64,

    /// Max EV
    #[structopt(long)]
    ev_max: f64,

    /// EV step
    #[structopt(long, default_value = "1.0")]
    ev_step: f64,
}

#[derive(StructOpt)]
enum Command {
    /// Runs an interactive image viewer (default)
    View,
    /// Batch-processes images
    Batch(BatchCmd),
}

fn main() -> anyhow::Result<()> {
    let opt = Opt::from_args();

    simple_logger::SimpleLogger::new()
        .with_level(log::LevelFilter::Info)
        .with_utc_timestamps()
        .init()
        .unwrap();

    let el = EventLoop::new();
    let wb = WindowBuilder::new().with_title("notorious6");

    let windowed_context = ContextBuilder::new()
        .with_gl_debug_flag(true)
        .with_gl_profile(glutin::GlProfile::Core)
        .build_windowed(wb, &el)
        .unwrap();

    let windowed_context = unsafe { windowed_context.make_current().unwrap() };
    let gl = gl::Gl::load_with(|symbol| windowed_context.get_proc_address(symbol) as *const _);
    setup::setup_basic_gl_state(&gl);

    let mut state = AppState::new(opt.input, &gl)?;
    let mut exit_upon_batch_completion = false;

    if let Some(Command::Batch(BatchCmd {
        shader,
        ev_min,
        ev_max,
        ev_step,
    })) = opt.cmd
    {
        state
            .request_batch(ev_min, ev_max, ev_step, &shader)
            .context("state.request_batch")?;
        exit_upon_batch_completion = true;
    }

    el.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Poll;

        match event {
            Event::LoopDestroyed => {}
            Event::WindowEvent { event, .. } => match event {
                WindowEvent::Resized(physical_size) => windowed_context.resize(physical_size),
                WindowEvent::CloseRequested => *control_flow = ControlFlow::Exit,
                _ => {
                    if matches!(state.handle_window_event(event), NeedsRedraw::Yes) {
                        windowed_context.window().request_redraw();
                    }
                }
            },
            Event::MainEventsCleared => {
                if matches!(state.update(&gl), NeedsRedraw::Yes) {
                    windowed_context.window().request_redraw();
                }

                windowed_context.window().set_title(&format!(
                    "{} | EV {:2.2} | {}",
                    state
                        .current_image_name()
                        .unwrap_or_else(|| "notorious6".to_owned()),
                    state.ev,
                    state.current_shader()
                ));

                match state.process_batched_requests(&gl) {
                    Ok(_) => (),
                    Err(err) => {
                        log::error!("Batch processing error: {:?}", err);
                        *control_flow = ControlFlow::Exit
                    }
                }

                if state.pending_image_capture.is_empty() && exit_upon_batch_completion {
                    *control_flow = ControlFlow::Exit;
                }
            }
            Event::RedrawRequested(_) => {
                let window_size = windowed_context.window().inner_size();
                state.draw_frame(
                    &gl,
                    [window_size.width as usize, window_size.height as usize],
                );
                windowed_context.swap_buffers().unwrap();
            }
            _ => (),
        }
    });
}
