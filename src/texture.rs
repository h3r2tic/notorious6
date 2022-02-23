use gl::types::{GLenum, GLuint};

use crate::image_loading::ImageRgb32f;

#[derive(Clone, Copy)]
pub struct Texture {
    pub ty: GLenum, // gl::TEXTURE_2D
    pub size: [usize; 2],
    pub id: GLuint,
    pub internal_format: GLenum,
}

impl Texture {
    pub fn new_2d(gl: &gl::Gl, image: &ImageRgb32f) -> Self {
        let ty = gl::TEXTURE_2D;
        let internal_format = gl::RGBA32F;

        unsafe {
            let mut texture_id = 0;
            gl.GenTextures(1, &mut texture_id);
            gl.BindTexture(ty, texture_id);
            gl.TexStorage2D(
                ty,
                1,
                internal_format,
                image.size[0] as _,
                image.size[1] as _,
            );
            gl.TexSubImage2D(
                ty,
                0,
                0,
                0,
                image.size[0] as _,
                image.size[1] as _,
                gl::RGB,
                gl::FLOAT,
                std::mem::transmute(image.data.as_ptr()),
            );
            gl.TexParameteri(ty, gl::TEXTURE_MIN_FILTER, gl::LINEAR as i32);
            gl.TexParameteri(ty, gl::TEXTURE_MAG_FILTER, gl::LINEAR as i32);
            gl.TexParameteri(ty, gl::TEXTURE_WRAP_S, gl::CLAMP_TO_EDGE as i32);
            gl.TexParameteri(ty, gl::TEXTURE_WRAP_T, gl::CLAMP_TO_EDGE as i32);

            Texture {
                ty,
                id: texture_id,
                size: image.size,
                internal_format,
            }
        }
    }

    pub fn new_1d(gl: &gl::Gl, width: u32, internal_format: GLenum) -> Self {
        let ty = gl::TEXTURE_1D;

        unsafe {
            let mut texture_id = 0;
            gl.GenTextures(1, &mut texture_id);
            gl.BindTexture(ty, texture_id);
            gl.TexStorage1D(ty, 1, internal_format, width as _);
            gl.TexParameteri(ty, gl::TEXTURE_MIN_FILTER, gl::LINEAR as i32);
            gl.TexParameteri(ty, gl::TEXTURE_MAG_FILTER, gl::LINEAR as i32);

            // TODO: make configurable
            gl.TexParameteri(ty, gl::TEXTURE_WRAP_S, gl::REPEAT as i32);

            Texture {
                ty,
                id: texture_id,
                size: [width as _, 1],
                internal_format,
            }
        }
    }
}
