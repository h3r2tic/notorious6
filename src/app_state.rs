use crate::{
    fbo::Fbo,
    image_pool::*,
    shader::{AnyShadersChanged, ShaderKey, ShaderLib},
    texture::Texture,
};
use anyhow::Context;
use glutin::event::{ElementState, KeyboardInput, MouseButton, VirtualKeyCode, WindowEvent};
use jpeg_encoder::{ColorType, Encoder};
use std::{
    ffi::c_void,
    path::{Path, PathBuf},
    sync::Arc,
};
use turbosloth::LazyCache;

#[derive(Default)]
struct InteractionState {
    dragging_ev: bool,
    last_cursor_position: [f64; 2],
}

pub struct PendingImageCapture {
    ev: f64,
    file_path: PathBuf,
    image_index: usize,
    shader_index: usize,
}

pub struct AppState {
    image_pool: ImagePool,
    current_image: usize,
    shader_lib: ShaderLib,
    current_shader: usize,
    _lazy_cache: Arc<LazyCache>,
    shaders: Vec<ShaderKey>,
    interaction: InteractionState,
    pub pending_image_capture: Vec<PendingImageCapture>,
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
        let shaders: Vec<ShaderKey> = std::fs::read_dir(shaders_folder)
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
            pending_image_capture: Default::default(),
            ev: 0.0,
        })
    }

    pub fn compile_shaders(&mut self, gl: &gl::Gl) -> AnyShadersChanged {
        self.shader_lib.compile_all(gl)
    }

    pub fn process_batched_requests(&mut self, gl: &gl::Gl) -> anyhow::Result<()> {
        for pending in self.pending_image_capture.drain(..) {
            let texture = match self.image_pool.get_texture(pending.image_index, gl) {
                Some(texture) => texture,
                None => continue,
            };

            let fbo = Fbo::new(gl, texture.size);
            fbo.bind(gl);

            let shader = self
                .shader_lib
                .get_shader_gl_handle(&self.shaders[pending.shader_index])
                .expect("get_shader_gl_handle");

            draw_texture(gl, texture, shader, texture.size, pending.ev);
            Self::capture_screenshot(gl, texture, &pending.file_path)?;
            log::info!("Saved {:?}", pending.file_path);

            fbo.destroy(gl);
        }

        Ok(())
    }

    pub fn draw_frame(&mut self, gl: &gl::Gl, physical_window_size: [usize; 2]) {
        let texture = self.image_pool.get_texture(self.current_image, gl);

        unsafe {
            let shader = self
                .shader_lib
                .get_shader_gl_handle(&self.shaders[self.current_shader]);

            if let Some((texture, shader)) = texture.zip(shader) {
                let fbo = Fbo::new(gl, texture.size);
                fbo.bind(gl);

                draw_texture(gl, texture, shader, texture.size, self.ev);

                let width_frac: f64 = texture.size[0] as f64 / physical_window_size[0] as f64;
                let height_frac: f64 = texture.size[1] as f64 / physical_window_size[1] as f64;
                let fit_frac = width_frac.max(height_frac);
                let width_frac = width_frac / fit_frac;
                let height_frac = height_frac / fit_frac;

                let width = (physical_window_size[0] as f64 * width_frac) as i32;
                let height = (physical_window_size[1] as f64 * height_frac) as i32;
                let x_offset = (physical_window_size[0] as i32 - width) / 2;
                let y_offset = (physical_window_size[1] as i32 - height) / 2;

                fbo.unbind(gl);
                fbo.bind_read(gl);

                gl.ClearColor(0.1, 0.1, 0.1, 1.0);
                gl.Clear(gl::COLOR_BUFFER_BIT);
                gl.BlitFramebuffer(
                    0,
                    0,
                    texture.size[0] as _,
                    texture.size[1] as _,
                    x_offset,
                    y_offset,
                    x_offset + width,
                    y_offset + height,
                    gl::COLOR_BUFFER_BIT,
                    gl::LINEAR,
                );

                fbo.unbind_read(gl);
                fbo.destroy(gl);
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

    fn capture_screenshot(gl: &gl::Gl, texture: &Texture, file_path: &Path) -> anyhow::Result<()> {
        let mut pixels = vec![0u8; texture.size.into_iter().product::<usize>() * 4];

        if let Some(parent_dir) = file_path.parent() {
            std::fs::create_dir_all(parent_dir)?;
        }

        unsafe {
            gl.PixelStorei(gl::UNPACK_ALIGNMENT, 1);
            gl.ReadPixels(
                0,
                0,
                texture.size[0] as _,
                texture.size[1] as _,
                gl::RGBA,
                gl::UNSIGNED_BYTE,
                pixels.as_mut_ptr() as *mut c_void,
            );
        }

        // Flip it
        {
            let mut pixels = pixels.as_mut_slice();
            let row_bytes = texture.size[0] * 4;
            while pixels.len() >= row_bytes * 2 {
                let (a, rest) = pixels.split_at_mut(row_bytes);
                pixels = rest;
                let (rest, b) = pixels.split_at_mut(pixels.len() - row_bytes);
                pixels = rest;
                a.swap_with_slice(b);
            }
        }

        // Create new encoder that writes to a file with maximum quality (100)
        let encoder = Encoder::new_file(file_path, 90)
            .with_context(|| format!("Failed to create {:?}", file_path))?;

        encoder
            .encode(
                &pixels,
                texture.size[0] as _,
                texture.size[1] as _,
                ColorType::Rgba,
            )
            .context("encoder.encode")?;

        Ok(())
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
            Some(VirtualKeyCode::F12) => {
                self.pending_image_capture = vec![PendingImageCapture {
                    ev: self.ev,
                    file_path: "screenshot.jpg".into(),
                    image_index: self.current_image,
                    shader_index: self.current_shader,
                }];
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

    pub fn current_image_name(&self) -> Option<String> {
        self.image_pool
            .get_image_path(self.current_image)
            .and_then(|path| Some(path.file_name()?.to_string_lossy().as_ref().to_owned()))
    }

    pub fn request_batch(
        &mut self,
        ev_min: f64,
        ev_max: f64,
        ev_step: f64,
        shader_name: &str,
    ) -> anyhow::Result<()> {
        let root_dir = &PathBuf::from("batch");
        let shader_index = self
            .shaders
            .iter()
            .position(|shader| shader.name() == shader_name)
            .ok_or_else(|| anyhow::anyhow!("Unknown shader {:?}", shader_name))?;

        let mut batch = {
            let slf: &AppState = self;
            let image_count = self.image_pool.image_count();
            (0..image_count)
                .flat_map(|image_index| {
                    slf.image_pool
                        .get_image_path(image_index)
                        .into_iter()
                        .flat_map(move |image_path| {
                            let step_count =
                                ((ev_max - ev_min) / ev_step + 0.5).ceil().max(1.0) as usize;

                            (0..step_count).map(move |step_index| {
                                let ev = ev_min + ev_step * step_index as f64;

                                PendingImageCapture {
                                    ev,
                                    file_path: root_dir
                                        .join(image_path.file_name().unwrap())
                                        .join(format!("{:03} - EV {}.jpg", step_index, ev)),
                                    image_index,
                                    shader_index,
                                }
                            })
                        })
                })
                .collect::<Vec<PendingImageCapture>>()
        };

        self.pending_image_capture.append(&mut batch);

        Ok(())
    }
}

fn draw_texture(gl: &gl::Gl, texture: &Texture, shader_program: u32, size: [usize; 2], ev: f64) {
    unsafe {
        gl.Viewport(0, 0, size[0] as _, size[1] as _);

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
    }
}
