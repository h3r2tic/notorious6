pub struct Fbo {
    fbo: u32,
    rbo: u32,
}

impl Fbo {
    pub fn new(gl: &gl::Gl, size: [usize; 2]) -> Self {
        unsafe {
            let mut fbo: u32 = 0;
            gl.GenFramebuffers(1, &mut fbo);
            assert!(fbo != 0);

            gl.BindFramebuffer(gl::FRAMEBUFFER, fbo);

            let mut rbo = 0;
            gl.GenRenderbuffers(1, &mut rbo);
            gl.BindRenderbuffer(gl::RENDERBUFFER, rbo);
            gl.RenderbufferStorage(
                gl::RENDERBUFFER,
                gl::SRGB8_ALPHA8,
                size[0] as _,
                size[1] as _,
            );
            gl.FramebufferRenderbuffer(
                gl::FRAMEBUFFER,
                gl::COLOR_ATTACHMENT0,
                gl::RENDERBUFFER,
                rbo,
            );

            gl.BindFramebuffer(gl::FRAMEBUFFER, 0);

            Self { fbo, rbo }
        }
    }

    pub fn bind(&self, gl: &gl::Gl) {
        unsafe {
            gl.BindFramebuffer(gl::FRAMEBUFFER, self.fbo);
        }
    }

    pub fn bind_read(&self, gl: &gl::Gl) {
        unsafe {
            gl.BindFramebuffer(gl::READ_FRAMEBUFFER, self.fbo);
        }
    }

    pub fn unbind(&self, gl: &gl::Gl) {
        unsafe {
            gl.BindFramebuffer(gl::FRAMEBUFFER, 0);
        }
    }

    pub fn unbind_read(&self, gl: &gl::Gl) {
        unsafe {
            gl.BindFramebuffer(gl::READ_FRAMEBUFFER, 0);
        }
    }

    pub fn destroy(mut self, gl: &gl::Gl) {
        assert!(self.fbo != 0);

        self.unbind(gl);
        self.unbind_read(gl);
        unsafe {
            gl.DeleteRenderbuffers(1, &self.rbo);
            gl.DeleteFramebuffers(1, &self.fbo);
        }
        self.rbo = 0;
        self.fbo = 0;
    }
}

impl Drop for Fbo {
    fn drop(&mut self) {
        if self.fbo != 0 {
            log::error!("Fbo must be manually destroyed");
        }
    }
}
