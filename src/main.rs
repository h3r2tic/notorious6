mod app_state;
mod file;
mod image;
mod image_pool;
mod setup;
mod shader;
mod texture;

use app_state::*;
use glutin::event::{Event, WindowEvent};
use glutin::event_loop::{ControlFlow, EventLoop};
use glutin::window::WindowBuilder;
use glutin::ContextBuilder;
use shader::AnyShadersChanged;

fn main() -> anyhow::Result<()> {
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

    let mut state = AppState::new(&gl)?;

    el.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Poll;

        match event {
            Event::LoopDestroyed => {}
            Event::WindowEvent { event, .. } => match event {
                WindowEvent::Resized(physical_size) => windowed_context.resize(physical_size),
                WindowEvent::CloseRequested => *control_flow = ControlFlow::Exit,
                WindowEvent::KeyboardInput { input, .. } => {
                    if matches!(state.handle_keyboard_input(input), NeedsRedraw::Yes) {
                        windowed_context.window().request_redraw();
                    }
                }
                _ => (),
            },
            Event::MainEventsCleared => {
                if matches!(state.compile_shaders(&gl), AnyShadersChanged::Yes) {
                    windowed_context.window().request_redraw();
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
