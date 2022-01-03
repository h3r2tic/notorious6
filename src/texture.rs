use crate::image::ImageRgb32f;

pub struct Texture {
    pub id: u32,
}

impl Texture {
    pub fn new(gl: &gl::Gl, image: &ImageRgb32f) -> Self {
        unsafe {
            let mut texture_id = 0;
            gl.GenTextures(1, &mut texture_id);
            gl.BindTexture(gl::TEXTURE_2D, texture_id);
            gl.TexStorage2D(
                gl::TEXTURE_2D,
                1,
                gl::RGBA32F,
                image.size[0] as _,
                image.size[1] as _,
            );
            gl.TexSubImage2D(
                gl::TEXTURE_2D,
                0,
                0,
                0,
                image.size[0] as _,
                image.size[1] as _,
                gl::RGB,
                gl::FLOAT,
                std::mem::transmute(image.data.as_ptr()),
            );
            gl.TexParameteri(gl::TEXTURE_2D, gl::TEXTURE_MIN_FILTER, gl::LINEAR as i32);
            gl.TexParameteri(gl::TEXTURE_2D, gl::TEXTURE_MAG_FILTER, gl::LINEAR as i32);
            gl.TexParameteri(gl::TEXTURE_2D, gl::TEXTURE_WRAP_S, gl::CLAMP_TO_EDGE as i32);
            gl.TexParameteri(gl::TEXTURE_2D, gl::TEXTURE_WRAP_T, gl::CLAMP_TO_EDGE as i32);

            Texture { id: texture_id }
        }
    }
}
