use anyhow::Context;
use bytes::Bytes;
use gl::types::*;
use relative_path::RelativePathBuf;
use shader_prepper::gl_compiler::{compile_shader, ShaderCompilerOutput};
use std::sync::Arc;
use std::{ffi::CString, path::PathBuf};
use turbosloth::*;

#[derive(Clone, Hash)]
pub struct PreprocessShader {
    pub path: PathBuf,
}

pub struct PreprocessedShader {
    pub name: String,
    pub source: Vec<shader_prepper::SourceChunk>,
}

#[async_trait]
impl LazyWorker for PreprocessShader {
    type Output = anyhow::Result<PreprocessedShader>;

    async fn run(self, ctx: RunContext) -> Self::Output {
        let name = self
            .path
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "unknown".to_string());

        let file_path = self.path.to_str().unwrap().to_owned();
        let source = shader_prepper::process_file(
            &file_path,
            &mut ShaderIncludeProvider { ctx },
            String::new(),
        );
        let source = source.map_err(|err| anyhow::anyhow!("{}", err))?;

        Ok(PreprocessedShader { source, name })
    }
}

struct ShaderIncludeProvider {
    ctx: RunContext,
}

impl shader_prepper::IncludeProvider for ShaderIncludeProvider {
    type IncludeContext = String;

    fn get_include(
        &mut self,
        path: &str,
        parent_file: &Self::IncludeContext,
    ) -> std::result::Result<
        (String, Self::IncludeContext),
        shader_prepper::BoxedIncludeProviderError,
    > {
        let resolved_path = if let Some('/') = path.chars().next() {
            path.to_owned()
        } else {
            let mut folder: RelativePathBuf = parent_file.into();
            folder.pop();
            folder.join(path).as_str().to_string()
        };

        let blob: Arc<Bytes> = smol::block_on(
            crate::file::LoadFile::new(&resolved_path)
                .with_context(|| format!("Failed loading shader include {}", path))?
                .into_lazy()
                .eval(&self.ctx),
        )?;

        Ok((String::from_utf8(blob.to_vec())?, resolved_path))
    }
}

pub(crate) fn make_shader<'chunk>(
    gl: &gl::Gl,
    shader_type: GLenum,
    sources: impl Iterator<Item = &'chunk shader_prepper::SourceChunk>,
) -> anyhow::Result<u32> {
    unsafe {
        let compiled_shader = compile_shader(sources, |sources| {
            let handle = gl.CreateShader(shader_type);

            let (source_lengths, source_ptrs): (Vec<GLint>, Vec<*const GLchar>) = sources
                .iter()
                .map(|s| (s.len() as GLint, s.as_ptr() as *const GLchar))
                .unzip();

            gl.ShaderSource(
                handle,
                source_ptrs.len() as i32,
                source_ptrs.as_ptr(),
                source_lengths.as_ptr(),
            );
            gl.CompileShader(handle);

            let mut shader_ok: gl::types::GLint = 1;
            gl.GetShaderiv(handle, gl::COMPILE_STATUS, &mut shader_ok);

            if shader_ok != 1 {
                let mut log_len: gl::types::GLint = 0;
                gl.GetShaderiv(handle, gl::INFO_LOG_LENGTH, &mut log_len);

                let log_str = CString::from_vec_unchecked(vec![b'\0'; (log_len + 1) as usize]);
                gl.GetShaderInfoLog(
                    handle,
                    log_len,
                    std::ptr::null_mut(),
                    log_str.as_ptr() as *mut gl::types::GLchar,
                );

                gl.DeleteShader(handle);

                ShaderCompilerOutput {
                    artifact: None,
                    log: Some(log_str.to_string_lossy().into_owned()),
                }
            } else {
                ShaderCompilerOutput {
                    artifact: Some(handle),
                    log: None,
                }
            }
        });

        if let Some(shader) = compiled_shader.artifact {
            if let Some(log) = compiled_shader.log {
                log::info!("Shader compiler output: {}", log);
            }
            Ok(shader)
        } else {
            anyhow::bail!(
                "Shader failed to compile: {}",
                compiled_shader.log.as_deref().unwrap_or("Unknown error")
            );
        }
    }
}

pub(crate) fn make_program(gl: &gl::Gl, shaders: &[u32]) -> anyhow::Result<u32> {
    unsafe {
        let handle = gl.CreateProgram();
        for &shader in shaders.iter() {
            gl.AttachShader(handle, shader);
        }

        gl.LinkProgram(handle);

        let mut program_ok: gl::types::GLint = 1;
        gl.GetProgramiv(handle, gl::LINK_STATUS, &mut program_ok);

        if program_ok != 1 {
            let mut log_len: gl::types::GLint = 0;
            gl.GetProgramiv(handle, gl::INFO_LOG_LENGTH, &mut log_len);

            let log_str = CString::from_vec_unchecked(vec![b'\0'; (log_len + 1) as usize]);

            gl.GetProgramInfoLog(
                handle,
                log_len,
                std::ptr::null_mut(),
                log_str.as_ptr() as *mut gl::types::GLchar,
            );

            let log_str = log_str.to_string_lossy().into_owned();

            gl.DeleteProgram(handle);
            anyhow::bail!("Shader failed to link: {}", log_str);
        } else {
            Ok(handle)
        }
    }
}

#[derive(Hash, PartialEq, Eq, Clone, PartialOrd, Ord)]
pub struct ShaderKey {
    path: PathBuf,
}

impl ShaderKey {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub fn name(&self) -> String {
        self.path
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "unknown".to_string())
    }
}
