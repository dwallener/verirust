use std::process;

fn main() {
    if let Err(err) = verirust::dump_reference_artifacts(&verirust::repo_root()) {
        eprintln!("dump_reference failed: {err}");
        process::exit(1);
    }
}
