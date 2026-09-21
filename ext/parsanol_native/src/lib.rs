//! Parsanol Native Extension
//!
//! This is the native Rust extension for parsanol-ruby.
//! It compiles the parsanol-rs crate with Ruby FFI bindings enabled.

use magnus::{Error, Ruby};

/// Initialize the Parsanol native extension
///
/// This function sets up the Parsanol::Native module with all the
/// functions from parsanol-rs.
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    // The native surface is Ractor-callable (parsanol-ruby#59): parse
    // state lives in per-thread caches and Mutex-guarded plain-data
    // registries, no shared Ruby objects cross the boundary.
    unsafe { rb_sys::rb_ext_ractor_safe(true) };

    // Initialize the parsanol-rs ffi::ruby module
    // This sets up Parsanol::Native with all the functions
    parsanol::ffi::ruby::init(ruby)
}
