use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub const VOCAB_SIZE: usize = 256;
pub const SEQ_LEN: usize = 16;
pub const D_MODEL: usize = 32;
pub const N_HEADS: usize = 2;
pub const D_HEAD: usize = 16;
pub const D_FF: usize = 64;
pub const FRAC_BITS: i32 = 8;
pub const MASK_NEG: i16 = i16::MIN;
pub const ATTN_SCALE_Q88: i16 = 64;
pub const INV_D_MODEL_Q16: i32 = 2048;
pub const EPS_Q16: i32 = 1;

pub const CHECKPOINTS: [&str; 18] = [
    "x_tok",
    "x_in",
    "norm1_out",
    "q_flat",
    "k_flat",
    "v_flat",
    "scores_pre_mask",
    "scores_post_mask",
    "attn_probs",
    "ctx_flat",
    "attn_out",
    "resid1_out",
    "norm2_out",
    "ffn_h1",
    "ffn_relu",
    "ffn_out",
    "block_out",
    "logits",
];

const TOK_EMBEDDING_LEN: usize = VOCAB_SIZE * D_MODEL;
const POS_EMBEDDING_LEN: usize = SEQ_LEN * D_MODEL;
const NORM_LEN: usize = D_MODEL;
const MAT_DMODEL_DMODEL: usize = D_MODEL * D_MODEL;
const W1_LEN: usize = D_MODEL * D_FF;
const W2_LEN: usize = D_FF * D_MODEL;
const LM_HEAD_LEN: usize = D_MODEL * VOCAB_SIZE;

#[derive(Clone)]
pub struct Weights {
    pub tok_embedding: Vec<i16>,
    pub pos_embedding: Vec<i16>,
    pub norm1_weight: Vec<i16>,
    pub w_q: Vec<i16>,
    pub w_k: Vec<i16>,
    pub w_v: Vec<i16>,
    pub w_o: Vec<i16>,
    pub norm2_weight: Vec<i16>,
    pub w1: Vec<i16>,
    pub w2: Vec<i16>,
    pub lm_head: Vec<i16>,
}

pub struct Luts {
    pub exp: Vec<i16>,
    pub rsqrt: Vec<i16>,
    pub recip: Vec<i16>,
}

pub struct Checkpoints {
    pub x_tok: Vec<i16>,
    pub x_in: Vec<i16>,
    pub norm1_out: Vec<i16>,
    pub q_flat: Vec<i16>,
    pub k_flat: Vec<i16>,
    pub v_flat: Vec<i16>,
    pub scores_pre_mask: Vec<i16>,
    pub scores_post_mask: Vec<i16>,
    pub attn_probs: Vec<i16>,
    pub ctx_flat: Vec<i16>,
    pub attn_out: Vec<i16>,
    pub resid1_out: Vec<i16>,
    pub norm2_out: Vec<i16>,
    pub ffn_h1: Vec<i16>,
    pub ffn_relu: Vec<i16>,
    pub ffn_out: Vec<i16>,
    pub block_out: Vec<i16>,
    pub logits: Vec<i16>,
}

impl Checkpoints {
    pub fn entries(&self) -> [(&'static str, &[i16]); 18] {
        [
            ("x_tok", &self.x_tok),
            ("x_in", &self.x_in),
            ("norm1_out", &self.norm1_out),
            ("q_flat", &self.q_flat),
            ("k_flat", &self.k_flat),
            ("v_flat", &self.v_flat),
            ("scores_pre_mask", &self.scores_pre_mask),
            ("scores_post_mask", &self.scores_post_mask),
            ("attn_probs", &self.attn_probs),
            ("ctx_flat", &self.ctx_flat),
            ("attn_out", &self.attn_out),
            ("resid1_out", &self.resid1_out),
            ("norm2_out", &self.norm2_out),
            ("ffn_h1", &self.ffn_h1),
            ("ffn_relu", &self.ffn_relu),
            ("ffn_out", &self.ffn_out),
            ("block_out", &self.block_out),
            ("logits", &self.logits),
        ]
    }
}

pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

pub fn canonical_input_tokens() -> [u8; SEQ_LEN] {
    let mut tokens = [0u8; SEQ_LEN];
    let mut t = 0;
    while t < SEQ_LEN {
        tokens[t] = ((t * 7 + 3) % VOCAB_SIZE) as u8;
        t += 1;
    }
    tokens
}

pub fn load_weights(root: &Path) -> io::Result<Weights> {
    let data = fs::read(root.join("weights/weights_v1.bin"))?;
    let words = bytes_to_i16_vec(&data)?;
    let expected = TOK_EMBEDDING_LEN
        + POS_EMBEDDING_LEN
        + NORM_LEN
        + MAT_DMODEL_DMODEL
        + MAT_DMODEL_DMODEL
        + MAT_DMODEL_DMODEL
        + MAT_DMODEL_DMODEL
        + NORM_LEN
        + W1_LEN
        + W2_LEN
        + LM_HEAD_LEN;
    if words.len() != expected {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "unexpected weight count: got {}, expected {}",
                words.len(),
                expected
            ),
        ));
    }

    let mut offset = 0usize;
    let mut take = |len: usize| {
        let slice = words[offset..offset + len].to_vec();
        offset += len;
        slice
    };

    Ok(Weights {
        tok_embedding: take(TOK_EMBEDDING_LEN),
        pos_embedding: take(POS_EMBEDDING_LEN),
        norm1_weight: take(NORM_LEN),
        w_q: take(MAT_DMODEL_DMODEL),
        w_k: take(MAT_DMODEL_DMODEL),
        w_v: take(MAT_DMODEL_DMODEL),
        w_o: take(MAT_DMODEL_DMODEL),
        norm2_weight: take(NORM_LEN),
        w1: take(W1_LEN),
        w2: take(W2_LEN),
        lm_head: take(LM_HEAD_LEN),
    })
}

pub fn ensure_luts(root: &Path) -> io::Result<Luts> {
    let dir = root.join("spec/luts");
    fs::create_dir_all(&dir)?;
    let exp_path = dir.join("exp_lut.bin");
    let rsqrt_path = dir.join("rsqrt_lut.bin");
    let recip_path = dir.join("recip_lut.bin");

    if !exp_path.exists() {
        write_i16_le_file(&exp_path, &build_exp_lut())?;
    }
    if !rsqrt_path.exists() {
        write_i16_le_file(&rsqrt_path, &build_rsqrt_lut())?;
    }
    if !recip_path.exists() {
        write_i16_le_file(&recip_path, &build_recip_lut())?;
    }

    Ok(Luts {
        exp: bytes_to_i16_vec(&fs::read(exp_path)?)?,
        rsqrt: bytes_to_i16_vec(&fs::read(rsqrt_path)?)?,
        recip: bytes_to_i16_vec(&fs::read(recip_path)?)?,
    })
}

pub fn dump_reference_artifacts(root: &Path) -> io::Result<()> {
    let weights = load_weights(root)?;
    let luts = ensure_luts(root)?;
    let tokens = canonical_input_tokens();
    let checkpoints = run_inference(&weights, &luts, &tokens);

    let tests_dir = root.join("tests");
    let ckpt_dir = tests_dir.join("checkpoints_000");
    fs::create_dir_all(&ckpt_dir)?;
    fs::write(tests_dir.join("input_000.bin"), tokens)?;

    for (name, values) in checkpoints.entries() {
        write_i16_le_file(&ckpt_dir.join(format!("{name}.bin")), values)?;
    }

    Ok(())
}

pub fn run_inference(weights: &Weights, luts: &Luts, tokens: &[u8; SEQ_LEN]) -> Checkpoints {
    let x_tok = gather_token_embeddings(tokens, &weights.tok_embedding);
    let x_in = add_tensor_q88(&x_tok, &weights.pos_embedding);
    let norm1_out = rmsnorm(&x_in, &weights.norm1_weight, luts);
    let q_flat = matmul_q88(&norm1_out, SEQ_LEN, D_MODEL, &weights.w_q, D_MODEL);
    let k_flat = matmul_q88(&norm1_out, SEQ_LEN, D_MODEL, &weights.w_k, D_MODEL);
    let v_flat = matmul_q88(&norm1_out, SEQ_LEN, D_MODEL, &weights.w_v, D_MODEL);
    let scores_pre_mask = attention_scores(&q_flat, &k_flat);
    let scores_post_mask = apply_causal_mask(&scores_pre_mask);
    let attn_probs = softmax_heads(&scores_post_mask, luts);
    let ctx_flat = attention_context(&attn_probs, &v_flat);
    let attn_out = matmul_q88(&ctx_flat, SEQ_LEN, D_MODEL, &weights.w_o, D_MODEL);
    let resid1_out = add_tensor_q88(&x_in, &attn_out);
    let norm2_out = rmsnorm(&resid1_out, &weights.norm2_weight, luts);
    let ffn_h1 = matmul_q88(&norm2_out, SEQ_LEN, D_MODEL, &weights.w1, D_FF);
    let ffn_relu = relu_q88(&ffn_h1);
    let ffn_out = matmul_q88(&ffn_relu, SEQ_LEN, D_FF, &weights.w2, D_MODEL);
    let block_out = add_tensor_q88(&resid1_out, &ffn_out);
    let logits = matmul_q88(&block_out, SEQ_LEN, D_MODEL, &weights.lm_head, VOCAB_SIZE);

    Checkpoints {
        x_tok,
        x_in,
        norm1_out,
        q_flat,
        k_flat,
        v_flat,
        scores_pre_mask,
        scores_post_mask,
        attn_probs,
        ctx_flat,
        attn_out,
        resid1_out,
        norm2_out,
        ffn_h1,
        ffn_relu,
        ffn_out,
        block_out,
        logits,
    }
}

fn gather_token_embeddings(tokens: &[u8; SEQ_LEN], table: &[i16]) -> Vec<i16> {
    let mut out = vec![0i16; SEQ_LEN * D_MODEL];
    for t in 0..SEQ_LEN {
        let token = tokens[t] as usize;
        let src = token * D_MODEL;
        let dst = t * D_MODEL;
        out[dst..dst + D_MODEL].copy_from_slice(&table[src..src + D_MODEL]);
    }
    out
}

fn add_tensor_q88(a: &[i16], b: &[i16]) -> Vec<i16> {
    a.iter()
        .zip(b.iter())
        .map(|(&lhs, &rhs)| saturate_i16(lhs as i32 + rhs as i32))
        .collect()
}

fn rmsnorm(x: &[i16], weight: &[i16], luts: &Luts) -> Vec<i16> {
    let mut out = vec![0i16; x.len()];
    for t in 0..SEQ_LEN {
        let base = t * D_MODEL;
        let row = &x[base..base + D_MODEL];
        let mut sum_sq = 0i32;
        for &value in row {
            sum_sq += (value as i32) * (value as i32);
        }
        let mean_sq = ((sum_sq as i64 * INV_D_MODEL_Q16 as i64) >> 16) as i32;
        let mean_sq_eps = mean_sq + EPS_Q16;
        let rsqrt = rsqrt_lookup(&luts.rsqrt, mean_sq_eps);
        for c in 0..D_MODEL {
            let y = requantize_q16_to_q8((row[c] as i32) * (rsqrt as i32));
            out[base + c] = requantize_q16_to_q8((y as i32) * (weight[c] as i32));
        }
    }
    out
}

fn matmul_q88(x: &[i16], n: usize, k: usize, w: &[i16], m: usize) -> Vec<i16> {
    let mut out = vec![0i16; n * m];
    for row in 0..n {
        for col in 0..m {
            let mut acc = 0i32;
            for inner in 0..k {
                acc += (x[row * k + inner] as i32) * (w[inner * m + col] as i32);
            }
            out[row * m + col] = requantize_q16_to_q8(acc);
        }
    }
    out
}

fn attention_scores(q_flat: &[i16], k_flat: &[i16]) -> Vec<i16> {
    let mut out = vec![0i16; N_HEADS * SEQ_LEN * SEQ_LEN];
    for h in 0..N_HEADS {
        for tq in 0..SEQ_LEN {
            for tk in 0..SEQ_LEN {
                let mut acc = 0i32;
                for d in 0..D_HEAD {
                    let qc = q_flat[tq * D_MODEL + h * D_HEAD + d] as i32;
                    let kc = k_flat[tk * D_MODEL + h * D_HEAD + d] as i32;
                    acc += qc * kc;
                }
                let dot_q88 = requantize_q16_to_q8(acc) as i32;
                let scaled = requantize_q16_to_q8(dot_q88 * ATTN_SCALE_Q88 as i32);
                out[(h * SEQ_LEN + tq) * SEQ_LEN + tk] = scaled;
            }
        }
    }
    out
}

fn apply_causal_mask(scores: &[i16]) -> Vec<i16> {
    let mut out = scores.to_vec();
    for h in 0..N_HEADS {
        for tq in 0..SEQ_LEN {
            for tk in (tq + 1)..SEQ_LEN {
                out[(h * SEQ_LEN + tq) * SEQ_LEN + tk] = MASK_NEG;
            }
        }
    }
    out
}

fn softmax_heads(scores: &[i16], luts: &Luts) -> Vec<i16> {
    let mut out = vec![0i16; scores.len()];
    for h in 0..N_HEADS {
        for tq in 0..SEQ_LEN {
            let row_base = (h * SEQ_LEN + tq) * SEQ_LEN;
            let row = &scores[row_base..row_base + SEQ_LEN];
            let mut max_val = i16::MIN;
            for &v in row {
                if v > max_val {
                    max_val = v;
                }
            }

            let mut exp_vals = [0i16; SEQ_LEN];
            let mut sum_exp = 0i32;
            for i in 0..SEQ_LEN {
                let shifted = (row[i] as i32 - max_val as i32).clamp(-2048, 0) as i16;
                let exp_val = exp_lookup(&luts.exp, shifted);
                exp_vals[i] = exp_val;
                sum_exp += exp_val as i32;
            }

            let inv_sum = recip_lookup(&luts.recip, sum_exp << 8);
            for i in 0..SEQ_LEN {
                out[row_base + i] = requantize_q16_to_q8((exp_vals[i] as i32) * (inv_sum as i32));
            }
        }
    }
    out
}

fn attention_context(attn_probs: &[i16], v_flat: &[i16]) -> Vec<i16> {
    let mut out = vec![0i16; SEQ_LEN * D_MODEL];
    for h in 0..N_HEADS {
        for tq in 0..SEQ_LEN {
            for d in 0..D_HEAD {
                let mut acc = 0i32;
                for tk in 0..SEQ_LEN {
                    let prob = attn_probs[(h * SEQ_LEN + tq) * SEQ_LEN + tk] as i32;
                    let value = v_flat[tk * D_MODEL + h * D_HEAD + d] as i32;
                    acc += prob * value;
                }
                out[tq * D_MODEL + h * D_HEAD + d] = requantize_q16_to_q8(acc);
            }
        }
    }
    out
}

fn relu_q88(x: &[i16]) -> Vec<i16> {
    x.iter().map(|&v| v.max(0)).collect()
}

pub fn requantize_q16_to_q8(x: i32) -> i16 {
    let shifted = if x >= 0 {
        x >> FRAC_BITS
    } else {
        -((-x) >> FRAC_BITS)
    };
    saturate_i16(shifted)
}

fn saturate_i16(x: i32) -> i16 {
    x.clamp(i16::MIN as i32, i16::MAX as i32) as i16
}

fn exp_lookup(lut: &[i16], shifted_q88: i16) -> i16 {
    let clamped = (shifted_q88 as i32).clamp(-2048, 0);
    let idx = (((clamped + 2048) as i64) * 1023 / 2048) as usize;
    lut[idx]
}

fn rsqrt_lookup(lut: &[i16], value_q16: i32) -> i16 {
    let max_q16 = 8 * 65536;
    let clamped = value_q16.clamp(0, max_q16);
    let idx = ((clamped as i64) * 4095 / max_q16 as i64) as usize;
    lut[idx]
}

fn recip_lookup(lut: &[i16], value_q16: i32) -> i16 {
    let max_q16 = 16 * 65536;
    let clamped = value_q16.clamp(0, max_q16);
    let idx = ((clamped as i64) * 4095 / max_q16 as i64) as usize;
    lut[idx]
}

fn build_exp_lut() -> Vec<i16> {
    let mut lut = Vec::with_capacity(1024);
    for idx in 0..1024 {
        let ratio = idx as f64 / 1023.0;
        let x = -8.0 + ratio * 8.0;
        lut.push(float_to_q88(x.exp()));
    }
    lut
}

fn build_rsqrt_lut() -> Vec<i16> {
    let mut lut = Vec::with_capacity(4096);
    for idx in 0..4096 {
        let ratio = idx as f64 / 4095.0;
        let x = ratio * 8.0;
        let y = if x <= 0.0 {
            255.99609375
        } else {
            1.0 / x.sqrt()
        };
        lut.push(float_to_q88(y));
    }
    lut
}

fn build_recip_lut() -> Vec<i16> {
    let mut lut = Vec::with_capacity(4096);
    for idx in 0..4096 {
        let ratio = idx as f64 / 4095.0;
        let x = ratio * 16.0;
        let y = if x <= 0.0 { 255.99609375 } else { 1.0 / x };
        lut.push(float_to_q88(y));
    }
    lut
}

fn float_to_q88(x: f64) -> i16 {
    let scaled = if x >= 0.0 {
        (x * 256.0).floor()
    } else {
        (x * 256.0).ceil()
    };
    saturate_i16(scaled as i32)
}

fn bytes_to_i16_vec(bytes: &[u8]) -> io::Result<Vec<i16>> {
    if bytes.len() % 2 != 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "byte length must be even for int16_le data",
        ));
    }

    let mut out = Vec::with_capacity(bytes.len() / 2);
    for chunk in bytes.chunks_exact(2) {
        out.push(i16::from_le_bytes([chunk[0], chunk[1]]));
    }
    Ok(out)
}

fn write_i16_le_file(path: &Path, values: &[i16]) -> io::Result<()> {
    let mut bytes = Vec::with_capacity(values.len() * 2);
    for &value in values {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    fs::write(path, bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_input_matches_spec() {
        assert_eq!(
            canonical_input_tokens(),
            [
                3, 10, 17, 24, 31, 38, 45, 52, 59, 66, 73, 80, 87, 94, 101, 108
            ]
        );
    }

    #[test]
    fn requantize_truncates_toward_zero() {
        assert_eq!(requantize_q16_to_q8(448), 1);
        assert_eq!(requantize_q16_to_q8(-448), -1);
        assert_eq!(requantize_q16_to_q8(255), 0);
        assert_eq!(requantize_q16_to_q8(-255), 0);
    }

    #[test]
    fn weight_blob_has_expected_length() {
        let weights = load_weights(&repo_root()).expect("weights should load");
        assert_eq!(weights.tok_embedding.len(), TOK_EMBEDDING_LEN);
        assert_eq!(weights.pos_embedding.len(), POS_EMBEDDING_LEN);
        assert_eq!(weights.norm1_weight.len(), NORM_LEN);
        assert_eq!(weights.w_q.len(), MAT_DMODEL_DMODEL);
        assert_eq!(weights.w1.len(), W1_LEN);
        assert_eq!(weights.w2.len(), W2_LEN);
        assert_eq!(weights.lm_head.len(), LM_HEAD_LEN);
    }
}
