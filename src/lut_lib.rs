use anyhow::Context;
use gl::types::*;
use std::path::PathBuf;
use std::sync::Arc;
use turbosloth::*;

use crate::shader::*;
use crate::texture::Texture;

#[derive(Hash, PartialEq, Eq, Clone, PartialOrd, Ord)]
pub struct LutDesc {
    pub width: u32,
    pub internal_format: GLenum,
    pub name: String,
    pub shader_path: PathBuf,
}

pub struct LutHandle(usize);

struct LutState {
    desc: LutDesc,
    shader: CompiledShader,
    texture: Texture,
}

struct CompiledShader {
    preprocessed: turbosloth::Lazy<PreprocessedShader>,
    gl_handle: Option<u32>,
}

impl CompiledShader {
    fn new(preprocessed: turbosloth::Lazy<PreprocessedShader>) -> Self {
        Self {
            preprocessed,
            gl_handle: None,
        }
    }
}

pub struct LutLib {
    luts: Vec<LutState>,
    lazy_cache: Arc<LazyCache>,
}

pub enum AnyLutsChanged {
    Yes,
    No,
}

impl LutLib {
    pub fn new(lazy_cache: &Arc<LazyCache>) -> Self {
        Self {
            luts: Default::default(),
            lazy_cache: lazy_cache.clone(),
        }
    }

    pub fn add_lut(&mut self, lut_desc: LutDesc, gl: &gl::Gl) -> LutHandle {
        let handle = LutHandle(self.luts.len());
        let texture = Texture::new_1d(gl, lut_desc.width, lut_desc.internal_format);
        assert_eq!(texture.internal_format, lut_desc.internal_format);

        self.luts.push(LutState {
            shader: CompiledShader::new(
                PreprocessShader {
                    path: lut_desc.shader_path.clone(),
                }
                .into_lazy(),
            ),
            texture,
            desc: lut_desc,
        });
        handle
    }

    pub fn compile_all(&mut self, gl: &gl::Gl) -> AnyLutsChanged {
        let mut any_shaders_changed = AnyLutsChanged::No;

        for lut in &mut self.luts {
            if !lut.shader.preprocessed.is_up_to_date() {
                let handle: anyhow::Result<u32> =
                    smol::block_on(lut.shader.preprocessed.eval(&self.lazy_cache))
                        .context("Preprocessing")
                        .and_then(|src| make_shader(gl, gl::COMPUTE_SHADER, src.source.iter()))
                        .context("Compiling the compute shader")
                        .and_then(|cs| make_program(gl, &[cs]));

                match handle {
                    Ok(handle) => {
                        log::info!("Shader compiled.");
                        lut.shader.gl_handle = Some(handle);
                        any_shaders_changed = AnyLutsChanged::Yes;

                        Self::compute_lut(lut, gl);
                    }
                    Err(err) => log::error!("Shader failed to compile: {:?}", err),
                }
            }
        }

        any_shaders_changed
    }

    pub fn iter(&self) -> impl Iterator<Item = (&LutDesc, &Texture)> {
        self.luts.iter().map(|lut| (&lut.desc, &lut.texture))
    }

    fn compute_lut(lut: &mut LutState, gl: &gl::Gl) {
        let shader_program = lut.shader.gl_handle.unwrap();

        unsafe {
            gl.UseProgram(shader_program);

            {
                let loc =
                    gl.GetUniformLocation(shader_program, "output_image\0".as_ptr() as *const i8);
                if loc != -1 {
                    let img_unit = 0;
                    gl.Uniform1i(loc, img_unit);
                    gl.BindImageTexture(
                        img_unit as _,
                        lut.texture.id,
                        0,
                        gl::FALSE,
                        0,
                        gl::READ_WRITE,
                        lut.texture.internal_format,
                    );
                }
            }

            let mut work_group_size: [i32; 3] = [0, 0, 0];
            gl.GetProgramiv(
                shader_program,
                gl::COMPUTE_WORK_GROUP_SIZE,
                &mut work_group_size[0],
            );

            fn div_up(a: u32, b: u32) -> u32 {
                (a + b - 1) / b
            }

            gl.DispatchCompute(div_up(lut.desc.width, work_group_size[0] as u32), 1, 1);
            gl.UseProgram(0);
        }
    }
}
