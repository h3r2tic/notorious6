use anyhow::Context;
use bytes::Bytes;
use gl::types::*;
use lazy_static::lazy_static;
use regex::Regex;
use relative_path::RelativePathBuf;
use std::collections::HashMap;
use std::iter;
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
    ) -> std::result::Result<(String, Self::IncludeContext), failure::Error> {
        let resolved_path = if let Some('/') = path.chars().next() {
            path.to_owned()
        } else {
            let mut folder: RelativePathBuf = parent_file.into();
            folder.pop();
            folder.join(path).as_str().to_string()
        };

        // println!("shader include '{}' resolved to '{}'", path, resolved_path);

        let blob: Arc<Bytes> = smol::block_on(
            crate::file::LoadFile::new(&resolved_path)
                .map_err(|err| {
                    failure::err_msg(format!("Failed loading shader include {}: {:?}", path, err))
                })?
                .into_lazy()
                .eval(&self.ctx),
        )
        .map_err(|err| failure::format_err!("{}", err))?;

        String::from_utf8(blob.to_vec())
            .map_err(|e| failure::format_err!("{}", e))
            .map(|ok| (ok, resolved_path))
    }
}

pub(crate) fn make_shader(
    gl: &gl::Gl,
    shader_type: u32,
    sources: &[shader_prepper::SourceChunk],
) -> anyhow::Result<u32> {
    unsafe {
        let handle = gl.CreateShader(shader_type);

        let preamble = shader_prepper::SourceChunk {
            source: "#version 430\n".to_string(),
            file: String::new(),
            line_offset: 0,
        };

        let mut source_lengths: Vec<GLint> = Vec::new();
        let mut source_ptrs: Vec<*const GLchar> = Vec::new();

        let mod_sources: Vec<_> = sources
            .iter()
            .enumerate()
            .map(|(i, s)| shader_prepper::SourceChunk {
                source: format!("#line 0 {}\n", i + 1) + &s.source,
                line_offset: s.line_offset,
                file: s.file.clone(),
            })
            .collect();

        for s in iter::once(&preamble).chain(mod_sources.iter()) {
            source_lengths.push(s.source.len() as GLint);
            source_ptrs.push(s.source.as_ptr() as *const GLchar);
        }

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

            let log_str = log_str.to_string_lossy().into_owned();

            lazy_static! {
                static ref INTEL_ERROR_RE: Regex =
                    Regex::new(r"(?m)^ERROR:\s*(\d+):(\d+)").unwrap();
            }

            lazy_static! {
                static ref NV_ERROR_RE: Regex = Regex::new(r"(?m)^(\d+)\((\d+)\)\s*").unwrap();
            }

            let error_replacement = |captures: &regex::Captures| -> String {
                let chunk = captures[1].parse::<usize>().unwrap().max(1) - 1;
                let line = captures[2].parse::<usize>().unwrap();
                format!(
                    "{}({})",
                    sources[chunk].file,
                    line + sources[chunk].line_offset
                )
            };

            let pretty_log = INTEL_ERROR_RE.replace_all(&log_str, error_replacement);
            let pretty_log = NV_ERROR_RE.replace_all(&pretty_log, error_replacement);

            gl.DeleteShader(handle);
            anyhow::bail!("Shader failed to compile: {}", pretty_log.to_string());
        } else {
            Ok(handle)
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

#[derive(Hash, PartialEq, Eq, Clone)]
pub struct ShaderKey {
    path: PathBuf,
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
        let vs = make_shader(
            gl,
            gl::VERTEX_SHADER,
            &[shader_prepper::SourceChunk {
                file: "no_file".to_string(),
                line_offset: 0,
                source: r#"
                    out vec2 uv;
                    void main()
                    {
                        uv = vec2(gl_VertexID & 1, gl_VertexID >> 1) * 2.0;
                        // Note: V flipped because our textures are flipped in memory
                        gl_Position = vec4(uv * vec2(2.0, -2.0) + vec2(-1.0, 1.0), 0, 1);
                    }"#
                .to_string(),
            }],
        )
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

        for shader in self.shaders.values_mut() {
            if !shader.preprocessed_ps.is_up_to_date() {
                let handle: anyhow::Result<u32> =
                    smol::block_on(shader.preprocessed_ps.eval(&self.lazy_cache))
                        .context("Preprocessing")
                        .and_then(|ps_src| make_shader(gl, gl::FRAGMENT_SHADER, &ps_src.source))
                        .context("Compiling the pixel shader")
                        .and_then(|ps| make_program(gl, &[self.vs_handle, ps]));

                match handle {
                    Ok(handle) => {
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
