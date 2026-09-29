fn main() {
    // MRI loadables on macOS resolve ruby symbols from the host process
    // at load time; cargo's cdylib link defaults to failing on undefined
    // symbols, so the flag must come from the top-level package.
    if cfg!(target_os = "macos") {
        println!("cargo:rustc-link-arg=-Wl,-undefined,dynamic_lookup");
    }
    println!("cargo:rerun-if-changed=build.rs");
}
