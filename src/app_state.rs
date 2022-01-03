use crate::image_pool::*;
use crate::shader::{AnyShadersChanged, ShaderKey, ShaderLib};
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

    pub fn draw_frame(&mut self, gl: &gl::Gl) {
        let texture = self
            .image_pool
            .get_texture(self.current_image, gl)
            .map(|tex| tex.id);

        unsafe {
            let shader = self.shader_lib.get_shader_gl_handle(&self.shaders[0]);

            if let Some((texture, shader)) = texture.zip(shader) {
                draw_fullscreen_texture(gl, texture, shader);
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

    pub fn handle_resize(&mut self, width: u32, height: u32, gl: &gl::Gl) {
        unsafe {
            gl.Viewport(0, 0, width as _, height as _);
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

fn draw_fullscreen_texture(gl: &gl::Gl, tex: u32, prog: u32) {
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
