mod app_state;
mod fbo;
mod file;
mod image_loading;
mod image_pool;
mod setup;
mod shader;
mod texture;

use std::path::PathBuf;

use app_state::*;
use glutin::event::{Event, WindowEvent};
use glutin::event_loop::{ControlFlow, EventLoop};
use glutin::window::WindowBuilder;
use glutin::ContextBuilder;
use shader::AnyShadersChanged;

use structopt::StructOpt;

#[derive(Debug, StructOpt)]
#[structopt(name = "notorious6", about = "HDR display mapping stuffs.")]
struct Opt {
    #[structopt(
        parse(from_os_str),
        default_value = "img",
        help = "A single file or a folder containing .exr or .hdr images"
    )]
    input: PathBuf,
}

fn main() -> anyhow::Result<()> {
    let opt = Opt::from_args();

    simple_logger::SimpleLogger::new()
        .with_level(log::LevelFilter::Info)
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
                if matches!(state.compile_shaders(&gl), AnyShadersChanged::Yes) {
                    windowed_context.window().request_redraw();
                }

                windowed_context.window().set_title(&format!(
                    "notorious6 | EV {:2.2} | {}",
                    state.ev,
                    state.current_shader()
                ));
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
