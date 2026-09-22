//! Vendored cdylib twin of parsanol-rs's `parsanol-ffi` crate, living in
//! the gem's ext workspace so the cross-gem build matrix can compile it
//! per platform triple. Mirrors parsanol-ffi: linking the rlib publishes
//! the `#[no_mangle] parsanol_c_*` exports; no wrappers.

// Force the dependency into the link even under aggressive stripping.
// Keep in sync with parsanol-rs parsanol-ffi/src/lib.rs.
#[allow(unused_imports)]
use parsanol::ffi::c::{
    parsanol_c_last_error, parsanol_c_parse, parsanol_c_parse_len, parsanol_c_register,
    parsanol_c_release,
};
