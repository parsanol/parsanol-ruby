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
    // Initialize the parsanol-rs ruby_ffi module
    // This sets up Parsanol::Native with all the functions
    parsanol::ruby_ffi::init(ruby)
}
