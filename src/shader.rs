use anyhow::Context;
use bytes::Bytes;
use gl::types::*;
use relative_path::RelativePathBuf;
use shader_prepper::gl_compiler::{compile_shader, ShaderCompilerOutput};
use std::collections::HashMap;
use std::iter::once;
use std::path::Path;
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

impl<'a> shader_prepper::IncludeProvider for ShaderIncludeProvider {
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

struct CompiledShader {
    preprocessed_ps: turbosloth::Lazy<PreprocessedShader>,
    gl_handle: Option<u32>,
}

impl CompiledShader {
    fn new(preprocessed_ps: turbosloth::Lazy<PreprocessedShader>) -> Self {
        Self {
            preprocessed_ps,
            gl_handle: None,
        }
    }
}

#[derive(Hash, PartialEq, Eq, Clone, PartialOrd, Ord)]
pub struct ShaderKey {
    path: PathBuf,
}

impl ShaderKey {
    pub fn name(&self) -> String {
        self.path
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "unknown".to_string())
    }
}

pub struct ShaderLib {
    shaders: HashMap<ShaderKey, CompiledShader>,
    vs_handle: u32,
    lazy_cache: Arc<LazyCache>,
}

pub enum AnyShadersChanged {
    Yes,
    No,
}

impl ShaderLib {
    pub fn new(lazy_cache: &Arc<LazyCache>, gl: &gl::Gl) -> Self {
        let source = shader_prepper::SourceChunk::from_file_source(
            "no_file",
            r#"
                #version 430
                out vec2 input_uv;
                void main()
                {
                    input_uv = vec2(gl_VertexID & 1, gl_VertexID >> 1) * 2.0;
                    // Note: V flipped because our textures are flipped in memory
                    gl_Position = vec4(input_uv * vec2(2.0, -2.0) + vec2(-1.0, 1.0), 0, 1);
                }"#,
        );

        let vs = make_shader(gl, gl::VERTEX_SHADER, once(&source))
            .expect("Vertex shader failed to compile");

        Self {
            shaders: Default::default(),
            vs_handle: vs,
            lazy_cache: lazy_cache.clone(),
        }
    }

    pub fn add_shader(&mut self, path: impl AsRef<Path>) -> ShaderKey {
        let path = path.as_ref().to_owned();
        let key = ShaderKey { path: path.clone() };
        self.shaders.insert(
            key.clone(),
            CompiledShader::new(PreprocessShader { path }.into_lazy()),
        );
        key
    }

    pub fn get_shader_gl_handle(&self, shader: &ShaderKey) -> Option<u32> {
        self.shaders.get(shader).and_then(|shader| shader.gl_handle)
    }

    pub fn compile_all(&mut self, gl: &gl::Gl) -> AnyShadersChanged {
        let mut any_shaders_changed = AnyShadersChanged::No;

        let ps_postamble = shader_prepper::SourceChunk::from_file_source(
            "postamble",
            r#"
            void main() {
                SHADER_MAIN_FN
            }
            "#,
        );

        for shader in self.shaders.values_mut() {
            if !shader.preprocessed_ps.is_up_to_date() {
                let handle: anyhow::Result<u32> =
                    smol::block_on(shader.preprocessed_ps.eval(&self.lazy_cache))
                        .context("Preprocessing")
                        .and_then(|ps_src| {
                            let sources = ps_src.source.iter().chain(once(&ps_postamble));

                            make_shader(gl, gl::FRAGMENT_SHADER, sources)
                        })
                        .context("Compiling the pixel shader")
                        .and_then(|ps| make_program(gl, &[self.vs_handle, ps]));

                match handle {
                    Ok(handle) => {
                        log::info!("Shader compiled.");
                        shader.gl_handle = Some(handle);
                        any_shaders_changed = AnyShadersChanged::Yes;
                    }
                    Err(err) => log::error!("Shader failed to compile: {:?}", err),
                }
            }
        }

        any_shaders_changed
    }
}
