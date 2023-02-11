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
        let internal_format = gl::RGB32F;

        let res = unsafe {
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

            let mut pbo = 0;
            gl.GenBuffers(1, &mut pbo);

            // Bind the PBO
            gl.BindBuffer(gl::PIXEL_UNPACK_BUFFER, pbo);

            //let t0 = std::time::Instant::now();
            let data_size: usize = image.data.len() * std::mem::size_of::<f32>();

            gl.BufferStorage(
                gl::PIXEL_UNPACK_BUFFER,
                data_size as _,
                std::ptr::null(),
                gl::MAP_READ_BIT
                    | gl::MAP_WRITE_BIT
                    | gl::MAP_PERSISTENT_BIT
                    | gl::MAP_COHERENT_BIT,
            );

            let mapped = gl.MapNamedBufferRange(
                pbo,
                0,
                data_size as _,
                gl::MAP_WRITE_BIT | gl::MAP_PERSISTENT_BIT | gl::MAP_COHERENT_BIT,
            );
            assert_ne!(mapped, std::ptr::null_mut());

            // Upload
            let mapped_slice = std::slice::from_raw_parts_mut(mapped as *mut u8, data_size);
            mapped_slice.copy_from_slice(std::slice::from_raw_parts(
                std::mem::transmute(image.data.as_ptr()),
                data_size,
            ));

            gl.TexSubImage2D(
                ty,
                0,
                0,
                0,
                image.size[0] as _,
                image.size[1] as _,
                gl::RGB,
                gl::FLOAT,
                std::ptr::null(),
            );
            // println!("Uploading the texture to the GPU took {:?}", t0.elapsed());

            gl.DeleteBuffers(1, &pbo);

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
        };

        res
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
