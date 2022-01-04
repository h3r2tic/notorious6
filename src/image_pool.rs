use crate::image::{self, ImageRgb32f};
use crate::texture::Texture;
use anyhow::Context;
use std::path::{Path, PathBuf};

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
    pub fn new(path: impl AsRef<Path>) -> anyhow::Result<Self> {
        let path = path.as_ref();

        if path.is_dir() {
            let dir = path
                .read_dir()
                .with_context(|| format!("Reading directory {:?}", path))?;
            Ok(Self {
                images: dir
                    .filter_map(|entry| {
                        let path = entry.ok()?.path();
                        (path.is_file() && path.extension() == Some(std::ffi::OsStr::new("exr")))
                            .then(|| PooledImage {
                                path: path.to_owned(),
                                image: PooledImageLoadStatus::NotLoaded,
                                texture: None,
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

    pub fn get_texture(&mut self, idx: usize, gl: &gl::Gl) -> Option<&Texture> {
        let img = self.images.get_mut(idx)?;

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

    pub fn image_count(&self) -> usize {
        self.images.len()
    }
}
