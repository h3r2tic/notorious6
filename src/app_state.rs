use crate::image_pool::*;
use crate::shader::{AnyShadersChanged, ShaderKey, ShaderLib};
use crate::texture::Texture;
use glutin::event::{KeyboardInput, VirtualKeyCode};
use std::sync::Arc;
use turbosloth::LazyCache;

pub struct AppState {
    image_pool: ImagePool,
    current_image: usize,
    shader_lib: ShaderLib,
    _lazy_cache: Arc<LazyCache>,
    shaders: Vec<ShaderKey>,
}

pub enum NeedsRedraw {
    Yes,
    No,
}

impl AppState {
    pub fn new(gl: &gl::Gl) -> anyhow::Result<Self> {
        let image_pool = ImagePool::new("img")?;
        let lazy_cache = LazyCache::create();

        let mut shader_lib = ShaderLib::new(&lazy_cache, gl);
        let shaders = vec![shader_lib.add_shader("shaders/linear.glsl")];

        Ok(Self {
            image_pool,
            current_image: 0,
            shader_lib,
            _lazy_cache: lazy_cache,
            shaders,
        })
    }

    pub fn compile_shaders(&mut self, gl: &gl::Gl) -> AnyShadersChanged {
        self.shader_lib.compile_all(gl)
    }

    pub fn draw_frame(&mut self, gl: &gl::Gl, physical_window_size: [usize; 2]) {
        let texture = self.image_pool.get_texture(self.current_image, gl);

        unsafe {
            let shader = self.shader_lib.get_shader_gl_handle(&self.shaders[0]);

            if let Some((texture, shader)) = texture.zip(shader) {
                gl.ClearColor(0.1, 0.1, 0.1, 1.0);
                gl.Clear(gl::COLOR_BUFFER_BIT);

                draw_texture(gl, texture, shader, physical_window_size);
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

    pub(crate) fn handle_keyboard_input(&mut self, input: KeyboardInput) -> NeedsRedraw {
        if !matches!(input.state, glutin::event::ElementState::Pressed) {
            return NeedsRedraw::No;
        }

        match input.virtual_keycode {
            Some(VirtualKeyCode::Left) => {
                self.current_image = (self.current_image
                    + self.image_pool.image_count().saturating_sub(1))
                    % self.image_pool.image_count();
                NeedsRedraw::Yes
            }
            Some(VirtualKeyCode::Right) => {
                self.current_image = (self.current_image + 1) % self.image_pool.image_count();
                NeedsRedraw::Yes
            }
            _ => NeedsRedraw::No,
        }
    }
}

fn draw_texture(
    gl: &gl::Gl,
    texture: &Texture,
    shader_program: u32,
    physical_window_size: [usize; 2],
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

        let loc = gl.GetUniformLocation(shader_program, "texture\0".as_ptr() as *const i8);
        let img_unit = 0;
        gl.Uniform1i(loc, img_unit);

        gl.DrawArrays(gl::TRIANGLES, 0, 3);
        gl.UseProgram(0);

        gl.Disable(gl::SCISSOR_TEST);
        gl.Disable(gl::FRAMEBUFFER_SRGB);
    }
}
