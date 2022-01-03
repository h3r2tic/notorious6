mod file;
mod image;
mod setup;
mod shader;
mod texture;

use std::sync::Arc;

use glutin::event::{Event, WindowEvent};
use glutin::event_loop::{ControlFlow, EventLoop};
use glutin::window::WindowBuilder;
use glutin::ContextBuilder;
use shader::{AnyShadersChanged, ShaderKey, ShaderLib};
use texture::Texture;
use turbosloth::LazyCache;

struct AppState {
    texture: Texture,
    shader_lib: ShaderLib,
    _lazy_cache: Arc<LazyCache>,
    shaders: Vec<ShaderKey>,
}

impl AppState {
    fn new(gl: &gl::Gl) -> anyhow::Result<Self> {
        let image = image::load_exr("sample.exr")?;
        let texture = texture::Texture::new(gl, image);
        let lazy_cache = LazyCache::create();

        let mut shader_lib = ShaderLib::new(&lazy_cache, gl);
        let shaders = vec![shader_lib.add_shader("shaders/linear.glsl")];

        Ok(Self {
            texture,
            shader_lib,
            _lazy_cache: lazy_cache,
            shaders,
        })
    }

    fn compile_shaders(&mut self, gl: &gl::Gl) -> AnyShadersChanged {
        self.shader_lib.compile_all(gl)
    }

    fn draw_frame(&mut self, gl: &gl::Gl) {
        unsafe {
            if let Some(shader) = self.shader_lib.get_shader_gl_handle(&self.shaders[0]) {
                draw_fullscreen_texture(gl, self.texture.id, shader);
            } else {
                gl.ClearColor(0.5, 0.0, 0.0, 1.0);
                gl.Clear(gl::COLOR_BUFFER_BIT);
            }
        }
    }

    fn handle_resize(&mut self, width: u32, height: u32, gl: &gl::Gl) {
        unsafe {
            gl.Viewport(0, 0, width as _, height as _);
        }
    }
}

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
                WindowEvent::Resized(physical_size) => {
                    windowed_context.resize(physical_size);
                    state.handle_resize(physical_size.width, physical_size.height, &gl);
                }
                WindowEvent::CloseRequested => *control_flow = ControlFlow::Exit,
                _ => (),
            },
            Event::MainEventsCleared => {
                if matches!(state.compile_shaders(&gl), AnyShadersChanged::Yes) {
                    windowed_context.window().request_redraw();
                }
            }
            Event::RedrawRequested(_) => {
                state.draw_frame(&gl);
                windowed_context.swap_buffers().unwrap();
            }
            _ => (),
        }
    });
}

pub fn draw_fullscreen_texture(gl: &gl::Gl, tex: u32, prog: u32) {
    unsafe {
        gl.UseProgram(prog);

        gl.ActiveTexture(gl::TEXTURE0);
        gl.BindTexture(gl::TEXTURE_2D, tex);

        let loc = gl.GetUniformLocation(prog, "texture\0".as_ptr() as *const i8);
        let img_unit = 0;
        gl.Uniform1i(loc, img_unit);

        gl.DrawArrays(gl::TRIANGLES, 0, 3);
        gl.UseProgram(0);
    }
}
