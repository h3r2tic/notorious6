use crate::image::{self, ImageRgb32f};
use crate::shader::{AnyShadersChanged, ShaderKey, ShaderLib};
use crate::texture::Texture;
use anyhow::Context;
use glutin::event::{KeyboardInput, VirtualKeyCode};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use turbosloth::LazyCache;

enum PooledImageLoadStatus {
    NotLoaded,
    FailedToLoad,
    Loaded(ImageRgb32f),
}

struct PooledImage {
    path: PathBuf,
    image: PooledImageLoadStatus,
    texture: Option<Texture>,
}

pub struct ImagePool {
    images: Vec<PooledImage>,
}

impl ImagePool {
    fn new(path: impl AsRef<Path>) -> anyhow::Result<Self> {
        let path = path.as_ref();

        if path.is_dir() {
            let dir = path
                .read_dir()
                .with_context(|| format!("Reading directory {:?}", path))?;
            Ok(Self {
                images: dir
                    .filter_map(|entry| {
                        let path = entry.ok()?.path();
                        (path.extension() == Some(std::ffi::OsStr::new("exr"))).then(|| {
                            PooledImage {
                                path: path.to_owned(),
                                image: PooledImageLoadStatus::NotLoaded,
                                texture: None,
                            }
                        })
                    })
                    .collect(),
            })
        } else {
            Ok(Self {
                images: vec![PooledImage {
                    path: path.to_owned(),
                    image: PooledImageLoadStatus::NotLoaded,
                    texture: None,
                }],
            })
        }
    }

    fn get_texture(&mut self, idx: usize, gl: &gl::Gl) -> Option<&Texture> {
        let img = &mut self.images[idx];
        if matches!(img.image, PooledImageLoadStatus::NotLoaded) {
            img.image = if let Ok(image) = image::load_exr(&img.path)
                .map_err(|err| log::error!("Failed to load {:?}: {:?}", img.path, err))
            {
                PooledImageLoadStatus::Loaded(image)
            } else {
                PooledImageLoadStatus::FailedToLoad
            };
        }

        match (&img.image, &mut img.texture) {
            (PooledImageLoadStatus::Loaded(loaded), target_image @ None) => {
                *target_image = Some(Texture::new(gl, loaded));
                target_image.as_ref()
            }
            (PooledImageLoadStatus::Loaded(_), Some(texture)) => Some(texture),
            _ => None,
        }
    }
}

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
                    + self.image_pool.images.len().saturating_sub(1))
                    % self.image_pool.images.len();
                NeedsRedraw::Yes
            }
            Some(VirtualKeyCode::Right) => {
                self.current_image = (self.current_image + 1) % self.image_pool.images.len();
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
