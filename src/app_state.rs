use crate::{
    image_pool::*,
    shader::{AnyShadersChanged, ShaderKey, ShaderLib},
    texture::Texture,
};
use anyhow::Context;
use glutin::event::{ElementState, KeyboardInput, MouseButton, VirtualKeyCode, WindowEvent};
use std::{path::PathBuf, sync::Arc};
use turbosloth::LazyCache;

#[derive(Default)]
struct InteractionState {
    dragging_ev: bool,
    last_cursor_position: [f64; 2],
}

pub struct AppState {
    image_pool: ImagePool,
    current_image: usize,
    shader_lib: ShaderLib,
    current_shader: usize,
    _lazy_cache: Arc<LazyCache>,
    shaders: Vec<ShaderKey>,
    interaction: InteractionState,
    pub ev: f64,
}

trait ModuloWrappingOps: Sized {
    fn modulo_wrapping_inc(self, modulo: Self) -> Self;
    fn modulo_wrapping_dec(self, modulo: Self) -> Self;
}

impl ModuloWrappingOps for usize {
    fn modulo_wrapping_inc(self, modulo: Self) -> Self {
        (self + 1) % modulo
    }

    fn modulo_wrapping_dec(self, modulo: Self) -> Self {
        (self + modulo.saturating_sub(1)) % modulo
    }
}

pub enum NeedsRedraw {
    Yes,
    No,
}

impl AppState {
    pub fn new(input_path: PathBuf, gl: &gl::Gl) -> anyhow::Result<Self> {
        let image_pool = ImagePool::new(input_path)?;
        let lazy_cache = LazyCache::create();

        let mut shader_lib = ShaderLib::new(&lazy_cache, gl);

        let shaders_folder = "shaders";
        let shaders = std::fs::read_dir(shaders_folder)
            .context("Reading the shaders/ directory")?
            .filter_map(|entry| {
                let path = entry.ok()?.path();
                (path.is_file() && path.extension() == Some(std::ffi::OsStr::new("glsl"))).then(
                    || {
                        shader_lib.add_shader(format!(
                            "{}/{}",
                            shaders_folder,
                            path.file_name().unwrap().to_string_lossy()
                        ))
                    },
                )
            })
            .collect();

        Ok(Self {
            image_pool,
            current_image: 0,
            shader_lib,
            current_shader: 0,
            _lazy_cache: lazy_cache,
            shaders,
            interaction: Default::default(),
            ev: 0.0,
        })
    }

    pub fn compile_shaders(&mut self, gl: &gl::Gl) -> AnyShadersChanged {
        self.shader_lib.compile_all(gl)
    }

    pub fn draw_frame(&mut self, gl: &gl::Gl, physical_window_size: [usize; 2]) {
        let texture = self.image_pool.get_texture(self.current_image, gl);

        unsafe {
            let shader = self
                .shader_lib
                .get_shader_gl_handle(&self.shaders[self.current_shader]);

            if let Some((texture, shader)) = texture.zip(shader) {
                gl.ClearColor(0.1, 0.1, 0.1, 1.0);
                gl.Clear(gl::COLOR_BUFFER_BIT);

                draw_texture(gl, texture, shader, physical_window_size, self.ev);
            } else {
                if shader.is_none() {
                    gl.ClearColor(0.5, 0.0, 0.0, 1.0);
                } else {
                    gl.ClearColor(0.0, 0.0, 0.0, 1.0);
                }

                gl.Clear(gl::COLOR_BUFFER_BIT);
            }
        }
    }

    fn handle_keyboard_input(&mut self, input: KeyboardInput) -> NeedsRedraw {
        if !matches!(input.state, glutin::event::ElementState::Pressed) {
            return NeedsRedraw::No;
        }

        match input.virtual_keycode {
            Some(VirtualKeyCode::Left) => {
                self.current_image = self
                    .current_image
                    .modulo_wrapping_dec(self.image_pool.image_count());
                NeedsRedraw::Yes
            }
            Some(VirtualKeyCode::Right) => {
                self.current_image = self
                    .current_image
                    .modulo_wrapping_inc(self.image_pool.image_count());
                NeedsRedraw::Yes
            }
            Some(VirtualKeyCode::Up) => {
                self.current_shader = self.current_shader.modulo_wrapping_inc(self.shaders.len());
                NeedsRedraw::Yes
            }
            Some(VirtualKeyCode::Down) => {
                self.current_shader = self.current_shader.modulo_wrapping_dec(self.shaders.len());
                NeedsRedraw::Yes
            }
            _ => NeedsRedraw::No,
        }
    }

    pub fn handle_window_event(&mut self, event: WindowEvent) -> NeedsRedraw {
        match event {
            WindowEvent::KeyboardInput { input, .. } => self.handle_keyboard_input(input),
            WindowEvent::CursorMoved { position, .. } => {
                let mut needs_redraw = NeedsRedraw::No;

                if self.interaction.dragging_ev {
                    self.ev += (self.interaction.last_cursor_position[1] - position.y) / 100.0;
                    needs_redraw = NeedsRedraw::Yes;
                }

                self.interaction.last_cursor_position = [position.x, position.y];
                needs_redraw
            }
            WindowEvent::MouseInput { state, button, .. } => {
                if matches!(button, MouseButton::Left) {
                    self.interaction.dragging_ev = matches!(state, ElementState::Pressed);
                }

                NeedsRedraw::No
            }
            _ => NeedsRedraw::No,
        }
    }

    pub fn current_shader(&self) -> String {
        self.shaders[self.current_shader].name()
    }
}

fn draw_texture(
    gl: &gl::Gl,
    texture: &Texture,
    shader_program: u32,
    physical_window_size: [usize; 2],
    ev: f64,
) {
    unsafe {
        gl.Enable(gl::FRAMEBUFFER_SRGB);
        gl.Enable(gl::SCISSOR_TEST);

        let width_frac: f64 = texture.size[0] as f64 / physical_window_size[0] as f64;
        let height_frac: f64 = texture.size[1] as f64 / physical_window_size[1] as f64;
        let fit_frac = width_frac.max(height_frac);
        let width_frac = width_frac / fit_frac;
        let height_frac = height_frac / fit_frac;

        let width = (physical_window_size[0] as f64 * width_frac) as i32;
        let height = (physical_window_size[1] as f64 * height_frac) as i32;
        let x_offset = (physical_window_size[0] as i32 - width) / 2;
        let y_offset = (physical_window_size[1] as i32 - height) / 2;

        gl.Scissor(x_offset, y_offset, width, height);
        gl.Viewport(x_offset, y_offset, width, height);

        gl.UseProgram(shader_program);

        gl.ActiveTexture(gl::TEXTURE0);
        gl.BindTexture(gl::TEXTURE_2D, texture.id);

        {
            let loc =
                gl.GetUniformLocation(shader_program, "input_texture\0".as_ptr() as *const i8);
            if loc != -1 {
                let img_unit = 0;
                gl.Uniform1i(loc, img_unit);
            }
        }

        {
            let loc = gl.GetUniformLocation(shader_program, "input_ev\0".as_ptr() as *const i8);
            if loc != -1 {
                gl.Uniform1f(loc, ev as f32);
            }
        }

        gl.DrawArrays(gl::TRIANGLES, 0, 3);
        gl.UseProgram(0);

        gl.Disable(gl::SCISSOR_TEST);
        gl.Disable(gl::FRAMEBUFFER_SRGB);
    }
}
