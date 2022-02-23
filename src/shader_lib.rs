use anyhow::Context;
use std::collections::HashMap;
use std::iter::once;
use std::path::Path;
use std::sync::Arc;
use turbosloth::*;

use crate::shader::*;

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
        let key = ShaderKey::new(&path);
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
