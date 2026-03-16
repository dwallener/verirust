use std::fs;
use std::io;

fn main() {
    if let Err(err) = run() {
        eprintln!("generate_frozen_rtl failed: {err}");
        std::process::exit(1);
    }
}

fn run() -> io::Result<()> {
    let root = verirust::repo_root();
    let weights = verirust::load_weights(&root)?;
    let luts = verirust::ensure_luts(&root)?;

    let generated_dir = root.join("rtl/generated");
    fs::create_dir_all(&generated_dir)?;
    let out_path = generated_dir.join("verirust_frozen_consts.svh");

    let mut out = String::new();
    out.push_str("`ifndef VERIRUST_FROZEN_CONSTS_SVH\n");
    out.push_str("`define VERIRUST_FROZEN_CONSTS_SVH\n\n");

    emit_i16_function(&mut out, "frozen_tok_embedding", &weights.tok_embedding);
    emit_i16_function(&mut out, "frozen_pos_embedding", &weights.pos_embedding);
    emit_i16_function(&mut out, "frozen_norm1_weight", &weights.norm1_weight);
    emit_i16_function(&mut out, "frozen_w_q", &weights.w_q);
    emit_i16_function(&mut out, "frozen_w_k", &weights.w_k);
    emit_i16_function(&mut out, "frozen_w_v", &weights.w_v);
    emit_i16_function(&mut out, "frozen_w_o", &weights.w_o);
    emit_i16_function(&mut out, "frozen_norm2_weight", &weights.norm2_weight);
    emit_i16_function(&mut out, "frozen_w1", &weights.w1);
    emit_i16_function(&mut out, "frozen_w2", &weights.w2);
    emit_i16_function(&mut out, "frozen_lm_head", &weights.lm_head);
    emit_i16_function(&mut out, "frozen_exp_lut", &luts.exp);
    emit_i16_function(&mut out, "frozen_rsqrt_lut", &luts.rsqrt);
    emit_i16_function(&mut out, "frozen_recip_lut", &luts.recip);

    out.push_str("`endif\n");
    fs::write(out_path, out)
}

fn emit_i16_function(out: &mut String, name: &str, values: &[i16]) {
    out.push_str(&format!("function signed [15:0] {name};\n"));
    out.push_str("input integer idx;\n");
    out.push_str("begin\n");
    out.push_str("    case (idx)\n");
    for (idx, value) in values.iter().enumerate() {
        out.push_str(&format!(
            "        {idx}: {name} = {};\n",
            verilog_i16_literal(*value)
        ));
    }
    out.push_str(&format!("        default: {name} = 16'sd0;\n"));
    out.push_str("    endcase\n");
    out.push_str("end\n");
    out.push_str("endfunction\n\n");
}

fn verilog_i16_literal(value: i16) -> String {
    if value < 0 {
        format!("-16'sd{}", -(value as i32))
    } else {
        format!("16'sd{}", value)
    }
}
