mod image;
mod shader;
mod texture;

use glutin::event::{Event, WindowEvent};
use glutin::event_loop::{ControlFlow, EventLoop};
use glutin::window::WindowBuilder;
use glutin::ContextBuilder;

use lazy_static::lazy_static;

fn setup_basic_gl_state(gl: &gl::Gl) {
    use std::ffi::CStr;

    unsafe {
        log::info!(
            "GL_VENDOR: {:?}",
            CStr::from_ptr(gl.GetString(gl::VENDOR) as *const i8)
        );
        log::info!(
            "GL_RENDERER: {:?}",
            CStr::from_ptr(gl.GetString(gl::RENDERER) as *const i8)
        );

        gl.DebugMessageCallback(Some(gl_debug_message), std::ptr::null_mut());

        // Disable everything by default
        gl.DebugMessageControl(
            gl::DONT_CARE,
            gl::DONT_CARE,
            gl::DONT_CARE,
            0,
            std::ptr::null_mut(),
            0,
        );

        gl.DebugMessageControl(
            gl::DONT_CARE,
            gl::DONT_CARE,
            gl::DONT_CARE,
            0,
            std::ptr::null_mut(),
            1,
        );

        gl.DebugMessageControl(
            gl::DEBUG_SOURCE_SHADER_COMPILER,
            gl::DONT_CARE,
            gl::DONT_CARE,
            0,
            std::ptr::null_mut(),
            0,
        );

        gl.Enable(gl::DEBUG_OUTPUT_SYNCHRONOUS);
        gl.Enable(gl::FRAMEBUFFER_SRGB);
    }
}

struct AppState {
    texture: Texture,
}

impl AppState {
    fn new(gl: &gl::Gl) -> anyhow::Result<Self> {
        let image = image::load_exr("sample.exr")?;
        let texture = texture::Texture::new(gl, image);

        Ok(Self { texture })
    }

    fn draw_frame(&mut self, gl: &gl::Gl) {
        unsafe {
            gl.ClearColor(0.2, 0.3, 0.3, 1.0);
            gl.Clear(gl::COLOR_BUFFER_BIT);

            draw_fullscreen_texture(gl, self.texture.id);
        }
    }

    fn handle_resize(&mut self, width: u32, height: u32, gl: &gl::Gl) {
        unsafe {
            gl.Viewport(0, 0, width as _, height as _);
        }
    }
}

fn main() -> anyhow::Result<()> {
    simple_logger::SimpleLogger::new().init().unwrap();

    let el = EventLoop::new();
    let wb = WindowBuilder::new().with_title("notorious6");

    let windowed_context = ContextBuilder::new()
        .with_gl_debug_flag(true)
        .with_gl_profile(glutin::GlProfile::Core)
        .with_vsync(true)
        .build_windowed(wb, &el)
        .unwrap();

    let windowed_context = unsafe { windowed_context.make_current().unwrap() };
    let gl = gl::Gl::load_with(|symbol| windowed_context.get_proc_address(symbol) as *const _);
    setup_basic_gl_state(&gl);

    let mut state = AppState::new(&gl)?;

    el.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

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
            Event::RedrawRequested(_) => {
                state.draw_frame(&gl);
                windowed_context.swap_buffers().unwrap();
            }
            _ => (),
        }
    });
}

extern "system" fn gl_debug_message(
    _source: u32,
    ty: u32,
    id: u32,
    severity: u32,
    _len: i32,
    message: *const i8,
    _param: *mut std::ffi::c_void,
) {
    unsafe {
        let s = std::ffi::CStr::from_ptr(message);

        #[allow(clippy::match_like_matches_macro)]
        let is_ignored_id = match id {
            131216 => true, // Program/shader state info: GLSL shader * failed to compile. WAT.
            131185 => true, // Buffer detailed info: (...) will use (...) memory as the source for buffer object operations.
            _ => false,
        };

        if !is_ignored_id {
            let is_important_type = matches!(
                ty,
                gl::DEBUG_TYPE_ERROR
                    | gl::DEBUG_TYPE_UNDEFINED_BEHAVIOR
                    | gl::DEBUG_TYPE_DEPRECATED_BEHAVIOR
                    | gl::DEBUG_TYPE_PORTABILITY
            );

            if !is_important_type {
                log::warn!("GL debug({}): {}\n", id, s.to_string_lossy());
            } else {
                log::warn!(
                    "OpenGL Debug message ({}, {:x}, {:x}): {}",
                    id,
                    ty,
                    severity,
                    s.to_string_lossy()
                );
            }
        }
    }
}

use shader::{make_program, make_shader};
use texture::Texture;

pub fn draw_fullscreen_texture(gl: &gl::Gl, tex: u32) {
    use parking_lot::Mutex;

    lazy_static! {
        static ref PROG: Mutex<Option<u32>> = Mutex::new(None);
    }

    if PROG.lock().is_none() {
        *PROG.lock() = {
            let vs = make_shader(
                gl,
                gl::VERTEX_SHADER,
                &[shader_prepper::SourceChunk {
                    file: "no_file".to_string(),
                    line_offset: 0,
                    source: r#"
                        out vec2 Frag_UV;
                        void main()
                        {
                            Frag_UV = vec2(gl_VertexID & 1, gl_VertexID >> 1) * 2.0;
                            gl_Position = vec4(Frag_UV * vec2(2.0, -2.0) + vec2(-1.0, 1.0), 0, 1);
                        }"#
                    .to_string(),
                }],
            )
            .expect("Vertex shader failed to compile");

            let ps = make_shader(
                gl,
                gl::FRAGMENT_SHADER,
                &[shader_prepper::SourceChunk {
                    file: "no_file".to_string(),
                    line_offset: 0,
                    source: r#"
                        uniform sampler2D Texture;
                        in vec2 Frag_UV;
                        out vec4 Out_Color;
                        void main()
                        {
                            ivec2 texSize = textureSize(Texture, 0);
                            Out_Color = textureLod(Texture, Frag_UV, 0);
                        }"#
                    .to_string(),
                }],
            )
            .expect("Pixel shader failed to compile");

            Some(make_program(gl, &[vs, ps]).expect("Shader failed to link"))
        };
    }
    let prog = PROG.lock().unwrap();

    unsafe {
        gl.UseProgram(prog);

        gl.ActiveTexture(gl::TEXTURE0);
        gl.BindTexture(gl::TEXTURE_2D, tex);

        let loc = gl.GetUniformLocation(prog, "Texture\0".as_ptr() as *const i8);
        let img_unit = 0;
        gl.Uniform1i(loc, img_unit);

        gl.DrawArrays(gl::TRIANGLES, 0, 3);
        gl.UseProgram(0);
    }
}
