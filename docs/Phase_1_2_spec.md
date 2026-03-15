
# Verirust Transformer Specification
## Phase 1 (Rust Reference) and Phase 2 (Verilog Flexible Hardware)

This document defines a **canonical transformer contract** designed so that:

1. A **Rust reference implementation (Phase 1)**
2. A **Verilog hardware implementation (Phase 2)**

can execute **identical inference**.

The specification is intentionally strict so that both implementations can match **bit‑for‑bit**.

The Rust fixed‑point implementation acts as the **semantic oracle** for hardware.

---

# Design Principles

The goal of this specification is **semantic determinism**.

Both implementations must agree on:

- tensor shapes
- numeric format
- operator ordering
- positional encoding
- normalization definition
- attention semantics
- weight layout
- masking behavior
- checkpoint outputs

If both implementations follow this contract, Phase 3 can compare:

- flexible hardware vs frozen hardware
- real synthesis compression
- real latency differences

---

# Model Dimensions

A deliberately small model is used.

```
vocab_size = 256
seq_len    = 16
d_model    = 32
n_heads    = 2
d_head     = 16
d_ff       = 64
n_layers   = 1
```

Constraint:

```
n_heads * d_head == d_model
```

---

# Input

Input tensor:

```
tokens [seq_len]
```

Type:

```
uint8
```

Range:

```
0 .. vocab_size-1
```

---

# Embeddings

## Token Embedding

Tensor:

```
tok_embedding [vocab_size, d_model]
```

Lookup rule:

```
x_tok[t, c] = tok_embedding[tokens[t], c]
```

---

## Positional Embedding

Learned absolute positional embeddings.

Tensor:

```
pos_embedding [seq_len, d_model]
```

Additive combination:

```
x_in[t, c] = x_tok[t, c] + pos_embedding[t, c]
```

---

# Transformer Block

Architecture uses **pre‑norm**.

```
a0 = x
a1 = norm1(a0)
a2 = mha(a1)
a3 = a0 + a2
a4 = norm2(a3)
a5 = ffn(a4)
a6 = a3 + a5
```

Output:

```
x_out = a6
```

Final logits:

```
logits = x_out @ lm_head
```

---

# RMSNorm

RMSNorm is used instead of LayerNorm.

Weights:

```
norm1_weight [d_model]
norm2_weight [d_model]
```

Definition:

```
rms = sqrt((1/d_model) * sum(x_i^2) + eps)
y_i = (x_i / rms) * weight_i
```

Constant:

```
eps = 1e-5
```

Canonical fixed-point execution is defined in the
`Canonical Fixed-Point Math Kernels` section below.

---

# Attention

Standard **causal multi‑head self‑attention**.

Projection weights:

```
w_q [d_model, d_model]
w_k [d_model, d_model]
w_v [d_model, d_model]
w_o [d_model, d_model]
```

No bias terms are used.

Projection:

```
q = x @ w_q
k = x @ w_k
v = x @ w_v
```

Reshape:

```
[seq_len, d_model] -> [seq_len, n_heads, d_head]
```

---

# Attention Scores

For each head:

```
scores = (q ⋅ k^T) * scale
```

Scale:

```
scale = 1 / sqrt(d_head)
```

With the chosen dimensions:

```
scale = 0.25
```

---

# Causal Mask

Allowed:

```
t_k <= t_q
```

Masked:

```
t_k > t_q
```

Masked scores replaced with:

```
MASK_NEG = minimum representable value
```

---

# Softmax

Row‑wise softmax.

```
m = max(scores_row)
z_i = exp(scores_i - m)
s = sum(z_i)
p_i = z_i / s
```

Rust reference may use full floating point exp.

Canonical fixed‑point mode must use **shared lookup tables**.

---

# Attention Output

Weighted sum:

```
ctx = sum(p * v)
```

Merge heads:

```
ctx_flat = concat(heads)
```

Projection:

```
attn_out = ctx_flat @ w_o
```

---

# Feed Forward Network

Weights:

```
w1 [d_model, d_ff]
w2 [d_ff, d_model]
```

Computation:

```
h1 = x @ w1
h2 = relu(h1)
h3 = h2 @ w2
```

Activation:

```
relu(x) = max(0, x)
```

---

# Output Head

Language model head:

```
lm_head [d_model, vocab_size]
```

Output:

```
logits = x_out @ lm_head
```

Shape:

```
[seq_len, vocab_size]
```

---

# Numeric Format

Two numeric modes are defined.

## Reference Mode

```
float32
```

Used only for debugging and validation.

---

## Canonical Mode

Signed fixed‑point.

```
Q8.8
```

Meaning:

```
value = int16 / 256
```

Accumulator width:

```
int32
```

Multiplication:

```
prod = (a * b) >> 8
```

Rounding rule:

```
truncate toward zero
```

Saturation occurs only when narrowing back to int16.

---

# Canonical Fixed-Point Math Kernels

This section defines the exact arithmetic procedures used in canonical mode.
Both Rust and Verilog implementations must follow these algorithms exactly.

Numeric format:

```
Q8.8 signed fixed point
int16 storage
int32 accumulators
frac_bits = 8
```

General multiplication rule:

```c
int32 prod = (int32)a * (int32)b;
int16 result = requantize_q16_to_q8(prod);
```

Saturation occurs only when narrowing to int16.

## RMSNorm Canonical Algorithm

Input tensor:

```
x [d_model]        (int16 Q8.8)
weight [d_model]   (int16 Q8.8)
```

Constants:

```
d_model = 32
eps = 1e-5
eps_q88 = 0x0001
```

Step 1 - Square and accumulate:

```text
sum_sq : int32 = 0

for i in 0..d_model-1
    sq = (int32)x[i] * x[i]        // Q16.16
    sum_sq += sq
```

Accumulator format after loop:

```
sum_sq : Q16.16
```

Step 2 - Compute mean square:

Multiply by reciprocal of d_model.

```
inv_d_model = 1 / 32 = 0.03125
inv_d_model_q16 = 2048
```

Compute:

```text
mean_sq = (sum_sq * inv_d_model_q16) >> 16
```

Result format:

```
mean_sq : Q16.16
```

Step 3 - Add epsilon:

```text
eps_q16 = 1e-5 * 65536 ~= 1
mean_sq_eps = mean_sq + eps_q16
```

Step 4 - Compute inverse sqrt:

Use LUT:

```text
rsqrt = rsqrt_lut(mean_sq_eps)
```

LUT specification:

```
input format : Q16.16
address bits : 12
input clamp  : [0 , 8.0]
entries      : 4096
output format: Q8.8
interpolation: none
```

Address mapping:

```text
clamped = clamp(mean_sq_eps, 0, 8 * 65536)
index = floor((clamped * 4095) / (8 * 65536))
rsqrt = rsqrt_lut[index]
```

LUT generation rule:

```text
for index in 0..4095
    x_real = index / 4095 * 8.0
    if x_real <= 0
        y_real = 255.99609375
    else
        y_real = 1 / sqrt(x_real)
    rsqrt_lut[index] = float_to_q88(y_real)
```

Step 5 - Normalize:

For each channel:

```text
y = (x[i] * rsqrt) >> 8
```

Result format:

```
Q8.8
```

Step 6 - Apply weight:

```text
out[i] = (y * weight[i]) >> 8
```

Output format:

```
Q8.8
```

## Softmax Canonical Algorithm

Input:

```
scores [seq_len]
format: Q8.8
seq_len = 16
```

Step 1 - Find row maximum:

```text
max_val = max(scores)
```

Format remains:

```
Q8.8
```

Step 2 - Subtract max:

```text
shifted[i] = scores[i] - max_val
```

Format:

```
Q8.8
```

Step 3 - Clamp exp input:

Clamp range:

```
[-8.0 , 0]
```

In Q8.8:

```
[-2048 , 0]
```

Step 4 - Compute exp using LUT:

```text
exp_val = exp_lut(shifted)
```

LUT specification:

```
input format  : Q8.8
input clamp   : [-8 , 0]
address bits  : 10
entries       : 1024
output format : Q8.8
interpolation : none
```

Address mapping:

```text
clamped = clamp(shifted, -2048, 0)
index = floor(((clamped + 2048) * 1023) / 2048)
exp_val = exp_lut[index]
```

LUT generation rule:

```text
for index in 0..1023
    x_real = -8.0 + (index / 1023) * 8.0
    y_real = exp(x_real)
    exp_lut[index] = float_to_q88(y_real)
```

Step 5 - Sum exponentials:

```text
sum_exp : int32 = 0

for i
    sum_exp += exp_val[i]
```

Format:

```
Q16.16 accumulator
```

Step 6 - Compute reciprocal of sum:

Use LUT:

```text
inv_sum = recip_lut(sum_exp)
```

LUT specification:

```
input format : Q16.16
address bits : 12
range        : [0 , 16]
output       : Q8.8
```

Address mapping:

```text
clamped = clamp(sum_exp, 0, 16 * 65536)
index = floor((clamped * 4095) / (16 * 65536))
inv_sum = recip_lut[index]
```

LUT generation rule:

```text
for index in 0..4095
    x_real = index / 4095 * 16.0
    if x_real <= 0
        y_real = 255.99609375
    else
        y_real = 1 / x_real
    recip_lut[index] = float_to_q88(y_real)
```

Step 7 - Normalize probabilities:

```text
prob[i] = (exp_val[i] * inv_sum) >> 8
```

Output format:

```
Q8.8
```

## Mask Sentinel

Masked attention entries must be replaced with:

```
MASK_NEG = -32768
```

Format:

```
int16 minimum
```

This guarantees masked tokens produce:

```text
exp(MASK_NEG) -> 0
```

after the exp LUT clamp.

## LUT Artifacts

The following files must exist in the repository:

```
spec/luts/exp_lut.bin
spec/luts/rsqrt_lut.bin
spec/luts/recip_lut.bin
```

Format:

```
little endian int16
```

Both Rust and Verilog must read the same LUT files.
They must not regenerate LUTs independently.

## LUT Mapping Rule

All canonical LUT lookups use linear mapping from the clamped input domain to
the integer address range:

```text
index = floor((normalized_input) * (entries - 1))
```

where `normalized_input` is the clamped input value rescaled into `[0, 1]`.

No interpolation, midpoint rounding, or alternate binning rule is permitted.

## Rounding Policy

Global rules:

```
multiply: int16 x int16 -> int32
requantize: truncation toward zero
rounding: truncate toward zero
saturation: only when narrowing to int16
```

No other rounding behavior is permitted.

## Canonical Compliance Requirement

The Verilog implementation must produce bit-exact matches with the Rust
canonical fixed-point implementation for all checkpoint tensors defined in
the main spec.

# Fixed-Point Operator Semantics (Canonical)

The following rules define exact arithmetic behavior for canonical Q8.8
execution. Both Rust and Verilog implementations must follow these rules
exactly.

## Numeric Types

```
storage type     : int16
format           : Q8.8
frac_bits        : 8
accumulator type : int32
```

Conversion between formats:

```text
real_value = stored_int16 / 256
```

## Multiply

Multiplication rule:

```text
prod32 = (int32)a * (int32)b
```

Intermediate format:

```
prod32 : Q16.16
```

Requantization to Q8.8:

```text
result16 = requantize_q16_to_q8(prod32)
```

## Right Shift Semantics

Right shifts must be arithmetic shifts.

Definition:

```text
shift(x, n) = arithmetic_shift_right(x, n)
```

Properties:

```text
shift(-1,1) = -1
shift(-2,1) = -1
shift(-3,1) = -2
```

Rust implementation must use signed shift.

Verilog must use:

```verilog
>>>
```

not logical `>>`.

Arithmetic shift is used only for internal scaling operations when the spec
explicitly says `arithmetic shift`.

## Accumulation Rules

All reductions and dot products accumulate in int32.

Dot product example:

```text
acc : int32 = 0

for i
    prod = (int32)a[i] * (int32)b[i]
    acc += prod
```

Format during accumulation:

```
acc : Q16.16
```

No saturation is applied during accumulation.
Overflow is prevented by accumulator width selection.

## Requantization

Requantization occurs only when narrowing from int32 -> int16.

Procedure:

```text
if x >= 0
    tmp = x >> frac_bits
else
    tmp = -((-x) >> frac_bits)

result = saturate_int16(tmp)
```

Where saturation is:

```text
if tmp > 32767  -> 32767
if tmp < -32768 -> -32768
```

This is truncation toward zero, not floor.

## Saturation Policy

Saturation occurs only at explicit narrowing points.

No saturation during:

```
multiplication
accumulation
mask insertion
max reduction
```

Saturation occurs when writing values to:

```
int16 storage tensors
checkpoint dumps
weight outputs
residual outputs
```

## Residual Add

Residual adds operate in int32 then narrow.

```text
tmp32 = (int32)a + (int32)b
out16 = saturate_int16(tmp32)
```

No intermediate narrowing is allowed.

## Mask Writes

Masked score entries must be written directly as int16:

```text
MASK_NEG = -32768
```

Mask writes bypass arithmetic pipelines and do not require narrowing.

## Score Scaling

Attention scaling must be performed using fixed-point multiply:

```text
scale = 0.25
scale_q88 = 64
```

Operation:

```text
scaled = (score * scale_q88) >> 8
```

Result format:

```
Q8.8
```

## Checkpoint Dump Format

All checkpoint tensors must be dumped in:

```
int16 little-endian
Q8.8 format
```

Checkpoint values must be fully narrowed and saturated before dump.

Procedure:

```text
value = requantize_q16_to_q8(accumulator)
write(value)
```

## Narrowing Policy

Values are narrowed to int16 only at these boundaries:

1. Output of linear projections
2. Output of normalization
3. Output of attention
4. Output of FFN layers
5. Residual outputs
6. Final logits
7. Checkpoint dumps

All intermediate math inside kernels remains int32.

## Canonical Determinism Rule

For canonical mode:

```text
Rust_fixed_point(x) == Verilog_fixed_point(x)
```

must hold bit-exactly for:

```
all checkpoint tensors
final logits
```

No tolerance or epsilon comparison is permitted.

## Requantization and Right-Shift Semantics

The canonical fixed-point spec distinguishes two separate operations:

1. arithmetic right shift
2. requantization with truncation toward zero

These are not the same for negative values and must not be conflated.

### Arithmetic Right Shift (Internal Operation)

Arithmetic right shift is defined as:

```text
shift(x, n) = sign-preserving right shift
```

Properties:

```text
shift(-1,1) = -1
shift(-2,1) = -1
shift(-3,1) = -2
```

This behavior corresponds to:

```
Rust: >> on signed integers
Verilog: >>>
```

Arithmetic shift is used only for internal scaling operations when the spec
explicitly says `arithmetic shift`.

### Canonical Requantization (Q16.16 -> Q8.8)

Requantization must truncate toward zero, not floor.

Therefore requantization must not rely on arithmetic shift alone.

Given:

```text
prod32 : int32  (Q16.16)
frac_bits = 8
```

Compute:

```text
if prod32 >= 0
    tmp = prod32 >> frac_bits
else
    tmp = -((-prod32) >> frac_bits)
```

Then apply saturation:

```text
result = saturate_int16(tmp)
```

This guarantees:

```text
+1.75 -> +1
-1.75 -> -1
```

Which is true truncation toward zero.

### Summary of Required Behavior

```text
internal shift : arithmetic shift
requantization : truncation toward zero
saturation     : only on int16 narrowing
```

### Reference Implementation (Canonical)

Rust reference helper:

```rust
fn requantize_q16_to_q8(x: i32) -> i16 {
    let shifted = if x >= 0 {
        x >> 8
    } else {
        -((-x) >> 8)
    };

    shifted.clamp(-32768, 32767) as i16
}
```

### Verilog Canonical Implementation

Verilog must implement the same behavior:

```verilog
function signed [15:0] requantize_q16_to_q8;
    input signed [31:0] x;
    reg signed [31:0] tmp;
begin
    if (x >= 0)
        tmp = x >>> 8;
    else
        tmp = -((-x) >>> 8);

    if (tmp > 32767)
        requantize_q16_to_q8 = 32767;
    else if (tmp < -32768)
        requantize_q16_to_q8 = -32768;
    else
        requantize_q16_to_q8 = tmp[15:0];
end
endfunction
```

### Canonical Compliance Requirement

All fixed-point helpers used by both implementations must ensure:

```text
Rust_requantize(x) == Verilog_requantize(x)
```

for every int32 input value.

This removes ambiguity between:

```text
floor
arithmetic shift
truncation toward zero
```

and guarantees deterministic cross-implementation behavior.

# Tensor Layout and Head Packing (Canonical)

This section defines the exact tensor indexing and memory layout rules used by
the canonical implementation.

All Rust and Verilog implementations must follow these rules exactly.

## Storage Layout

All tensors are stored in row-major order.

For tensor `[A, B]`:

```text
offset(a, b) = a * B + b
```

For tensor `[A, B, C]`:

```text
offset(a, b, c) = (a * B + b) * C + c
```

Binary serialization uses:

```
int16 little-endian
```

No implicit transpose is permitted when loading tensors.

## Matrix Multiply Convention

All matmuls follow the same rule:

```text
y = x @ W
```

Where:

```text
x : [N, K]
W : [K, M]
y : [N, M]
```

Interpretation:

```
vectors are row vectors
weight matrices are stored row-major
inner dimension is K
```

Computation:

```text
y[n, m] = sum_k (x[n, k] * W[k, m])
```

Implementations must not assume column-major loads or transposed weights.

## QKV Projection Layout

Projection outputs are computed as:

```text
q_flat = x @ w_q
k_flat = x @ w_k
v_flat = x @ w_v
```

Shape:

```text
q_flat : [seq_len, d_model]
```

With:

```text
d_model = n_heads * d_head
```

## Head Reshape Rule

The canonical reshape mapping is:

```text
q[t, h, d] = q_flat[t, h * d_head + d]
```

Where:

```text
t in [0, seq_len)
h in [0, n_heads)
d in [0, d_head)
```

Equivalent flat index:

```text
flat_channel = h * d_head + d
```

This rule applies identically to:

```
q
k
v
```

## Attention Score Computation

Scores are computed per head:

```text
scores[h, tq, tk] = dot(q[tq, h, :], k[tk, h, :])
```

Where:

```text
dot(a, b) = sum_d (a[d] * b[d])
```

Loop order is not constrained as long as numeric results match canonical math.

## Context Tensor Layout

Context output per head:

```text
ctx[h, t, d]
```

Shape:

```text
[n_heads, seq_len, d_head]
```

Definition:

```text
ctx[h, tq, d] = sum_tk (attn_probs[h, tq, tk] * v[tk, h, d])
```

## Head Concatenation Rule

The canonical head concatenation rule is:

```text
ctx_flat[t, h * d_head + d] = ctx[h, t, d]
```

This preserves the same packing order used by the QKV reshape.

Thus the channel ordering is:

```text
[head0_d0 ... head0_d15, head1_d0 ... head1_d15]
```

for `n_heads = 2`, `d_head = 16`.

## Output Projection Layout

The attention output projection is:

```text
attn_out = ctx_flat @ w_o
```

Shapes:

```text
ctx_flat : [seq_len, d_model]
w_o      : [d_model, d_model]
attn_out : [seq_len, d_model]
```

Again using row-vector matmul semantics.

## FFN Layout

First projection:

```text
h1 = x @ w1
```

Shapes:

```text
x  : [seq_len, d_model]
w1 : [d_model, d_ff]
h1 : [seq_len, d_ff]
```

Second projection:

```text
h2 = relu(h1)
h3 = h2 @ w2
```

Shapes:

```text
w2 : [d_ff, d_model]
```

## LM Head Layout

Final projection:

```text
logits = x_out @ lm_head
```

Shapes:

```text
x_out   : [seq_len, d_model]
lm_head : [d_model, vocab_size]
logits  : [seq_len, vocab_size]
```

## Canonical Channel Ordering

Channel order must be consistent across:

```
embeddings
attention projections
FFN layers
LM head
```

The channel index always corresponds to:

```text
flat_channel = head * d_head + local_dim
```

for tensors that represent head-packed data.

## Prohibited Layout Variations

Implementations must not:

```
transpose weight matrices
store per-head tensors separately
reorder head packing
reinterpret tensors as column-major
implicitly reshape weights during load
```

All reshaping must follow the canonical rules defined above.

## Compliance Requirement

Rust and Verilog implementations must produce identical intermediate tensors
when applying the reshape and concatenation rules above.

This ensures consistent attention head behavior and deterministic checkpoint
comparison.

# Weight Serialization

Files:

```
spec/model_spec.json
weights/weights_v1.bin
```

Tensor order in the binary blob:

1. tok_embedding
2. pos_embedding
3. norm1_weight
4. w_q
5. w_k
6. w_v
7. w_o
8. norm2_weight
9. w1
10. w2
11. lm_head

Storage layout:

```
row‑major
```

Binary type:

```
int16 little endian
```

---

# Canonical Checkpoints

Both implementations must expose the following tensors:

1. x_tok
2. x_in
3. norm1_out
4. q_flat
5. k_flat
6. v_flat
7. scores_pre_mask
8. scores_post_mask
9. attn_probs
10. ctx_flat
11. attn_out
12. resid1_out
13. norm2_out
14. ffn_h1
15. ffn_relu
16. ffn_out
17. block_out
18. logits

In canonical mode all checkpoints must match **bit‑exactly**.

---

# Canonical Test Vector and Checkpoint Generation

The repository must include one canonical inference example consisting of:

```
- a deterministic token input vector
- the expected output logits
- a complete checkpoint dump of all intermediate tensors
```

These artifacts are used to validate that Rust and Verilog implementations
produce identical results.

## Canonical Test Input

File:

```
tests/input_000.bin
```

Format:

```
uint8
length = seq_len
```

Deterministic token rule:

```text
token[t] = (t * 7 + 3) mod vocab_size
```

For the current model parameters:

```text
seq_len = 16
vocab_size = 256
```

The canonical input vector becomes:

```text
[3, 10, 17, 24, 31, 38, 45, 52,
 59, 66, 73, 80, 87, 94, 101, 108]
```

Stored as:

```
uint8 binary
```

## Canonical Checkpoint Dump

Reference execution must generate:

```
tests/checkpoints_000/
```

Containing the following tensors:

```
x_tok.bin
x_in.bin
norm1_out.bin
q_flat.bin
k_flat.bin
v_flat.bin
scores_pre_mask.bin
scores_post_mask.bin
attn_probs.bin
ctx_flat.bin
attn_out.bin
resid1_out.bin
norm2_out.bin
ffn_h1.bin
ffn_relu.bin
ffn_out.bin
block_out.bin
logits.bin
```

## Checkpoint Format

All checkpoint tensors must be written as:

```
int16
little-endian
Q8.8 fixed point
row-major
```

Shape metadata is provided by `model_spec.json`.

No compression or padding is allowed.

## Checkpoint Dump Rule

Every tensor must be narrowed and saturated to int16 before being written.

Procedure:

```text
tmp = arithmetic_shift_right(accumulator, frac_bits)
value = saturate_int16(tmp)
write(value)
```

This ensures checkpoint files match canonical storage format.

## Reference Generator

The Rust reference implementation must include a command:

```text
cargo run --bin dump_reference
```

which produces:

```text
tests/input_000.bin
tests/checkpoints_000/*
```

This command must:

1. load `weights/weights_v1.bin`
2. run canonical fixed-point inference
3. dump all checkpoint tensors
4. write deterministic outputs

## Acceptance Criteria

A compliant Verilog implementation must reproduce:

```text
tests/checkpoints_000/*
```

bit-for-bit.

Validation procedure:

```text
cmp rust_output.bin verilator_output.bin
```

must return equality for every checkpoint tensor.

## Repository Layout (Updated)

```text
verirust/
  spec/
    transformer_v1.md
    model_spec.json
  weights/
    weights_v1.bin
  tests/
    input_000.bin
    checkpoints_000/
  rust/
    dump_reference.rs
```

## Purpose

These artifacts provide a ground-truth inference trace so that:

```
Rust reference execution
Verilog simulation
synthesized hardware
```

can all be validated against the same deterministic example.

This eliminates ambiguity during Phase 2 bring-up.

---

# Phase 1: Rust Reference Implementation

The Rust implementation must:

- implement the complete forward pass
- support both float and Q8.8 execution
- load canonical weight blobs
- produce checkpoint dumps
- run deterministic test vectors

The Rust fixed‑point implementation defines the **canonical numeric behavior**.

---

# Phase 2: Verilog Flexible Hardware Implementation

The Verilog implementation must replicate the same semantics.

Scope:

- single sequence inference
- mutable weights
- synthesizable design

Interfaces:

- token input memory
- weight memory preload
- logits output memory
- control signals (start, reset, done)

Weights must **not be hard‑wired into logic** yet.

The design represents the **flexible hardware baseline**.

---

# Verification Requirements

Acceptance criteria:

- Verilog simulation matches Rust canonical outputs
- all checkpoint tensors match bit‑for‑bit
- design synthesizes successfully
- synthesis produces timing and area reports

---

# Phase 3 (Future)

After both implementations match:

1. freeze weights
2. synthesize optimized hardware
3. measure compression and speed differences
