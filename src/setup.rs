pub fn setup_basic_gl_state(gl: &gl::Gl) {
    use std::ffi::CStr;

    unsafe {
        log::info!(
            "GL_VENDOR: {:?}",
            CStr::from_ptr(gl.GetString(gl::VENDOR) as *const i8)
        );
        log::info!(
            "GL_RENDERER: {:?}",
            CStr::from_ptr(gl.GetString(gl::RENDERER) as *const i8)
        );

        gl.DebugMessageCallback(Some(gl_debug_message), std::ptr::null_mut());

        // Disable everything by default
        gl.DebugMessageControl(
            gl::DONT_CARE,
            gl::DONT_CARE,
            gl::DONT_CARE,
            0,
            std::ptr::null_mut(),
            0,
        );

        gl.DebugMessageControl(
            gl::DONT_CARE,
            gl::DONT_CARE,
            gl::DONT_CARE,
            0,
            std::ptr::null_mut(),
            1,
        );

        gl.DebugMessageControl(
            gl::DEBUG_SOURCE_SHADER_COMPILER,
            gl::DONT_CARE,
            gl::DONT_CARE,
            0,
            std::ptr::null_mut(),
            0,
        );

        gl.Enable(gl::DEBUG_OUTPUT_SYNCHRONOUS);
    }
}

extern "system" fn gl_debug_message(
    _source: u32,
    ty: u32,
    id: u32,
    severity: u32,
    _len: i32,
    message: *const i8,
    _param: *mut std::ffi::c_void,
) {
    unsafe {
        let s = std::ffi::CStr::from_ptr(message);

        #[allow(clippy::match_like_matches_macro)]
        let is_ignored_id = match id {
            131216 => true, // Program/shader state info: GLSL shader * failed to compile. WAT.
            131185 => true, // Buffer detailed info: (...) will use (...) memory as the source for buffer object operations.
            131169 => true, // Framebuffer detailed info: The driver allocated storage for renderbuffer
            131154 => true, // Pixel-path performance warning: Pixel transfer is synchronized with 3D rendering.
            _ => false,
        };

        if !is_ignored_id {
            let is_important_type = matches!(
                ty,
                gl::DEBUG_TYPE_ERROR
                    | gl::DEBUG_TYPE_UNDEFINED_BEHAVIOR
                    | gl::DEBUG_TYPE_DEPRECATED_BEHAVIOR
                    | gl::DEBUG_TYPE_PORTABILITY
            );

            if !is_important_type {
                log::warn!("GL debug({}): {}\n", id, s.to_string_lossy());
            } else {
                log::warn!(
                    "OpenGL Debug message ({}, {:x}, {:x}): {}",
                    id,
                    ty,
                    severity,
                    s.to_string_lossy()
                );
            }
        }
    }
}
