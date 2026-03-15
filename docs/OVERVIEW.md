Below is a clean spec skeleton for Phase 1 (Rust reference) and Phase 2 (Verilog-equivalent flexible hardware). The goal is not “a transformer.” The goal is one exact transformer definition that both implementations realize identically.

⸻

Top-level objective

Define a small, canonical, deterministic transformer inference core with:
	•	identical tensor shapes
	•	identical operator order
	•	identical numeric format
	•	identical memory layout
	•	identical positional encoding
	•	identical attention semantics
	•	identical normalization semantics
	•	identical weight serialization
	•	identical golden test vectors

This spec should be treated as the source of truth for both Rust and Verilog.

⸻

Global design principles
	1.	Inference-first
Phase 1 and 2 should implement forward pass only.
	2.	Fixed-shape first
No dynamic sequence lengths initially.
	3.	Fixed-point or explicitly reduced precision
Do not use unconstrained floating-point in Rust if Verilog will be fixed-point.
	4.	Single exact operator ordering
No “equivalent” formulations.
	5.	Golden vectors required
Every block must be testable against exact known outputs.
	6.	Minimal transformer
Small enough to reason about, large enough to contain the real issues.

⸻

Recommended baseline model

Use a deliberately small model:
	•	vocab_size = 256
	•	seq_len = 16
	•	d_model = 32
	•	n_heads = 2
	•	d_head = 16
	•	n_layers = 1
	•	d_ff = 64

This is enough to exercise:
	•	embeddings
	•	positional encoding
	•	Q/K/V projections
	•	scaled dot-product attention
	•	residuals
	•	normalization
	•	MLP
	•	output projection

⸻

Canonical architecture spec

Input
	•	Input tensor: tokens
	•	Shape: [seq_len]
	•	Type: unsigned integer token IDs
	•	Range: 0 .. vocab_size-1

Token embedding
	•	Embedding table shape: [vocab_size, d_model]
	•	Output shape: [seq_len, d_model]

Positional encoding

Pick one now and do not change it midstream.

Recommendation for first pass

Use learned absolute positional embeddings, not RoPE.

Reason:
	•	simpler in Verilog
	•	simpler serialization
	•	fewer trig / rotation edge cases
	•	easier golden-vector comparison

Positional embedding table:
	•	Shape: [seq_len, d_model]

Combined embedding:
	•	x = token_embedding + position_embedding

Transformer block

Use pre-norm for stability and simplicity of later training import.

Per layer:

x0 = input
x1 = LN1(x0)
x2 = MHA(x1)
x3 = x0 + x2
x4 = LN2(x3)
x5 = FFN(x4)
x6 = x3 + x5

Attention

Use standard causal scaled dot-product attention.

Projections

Single-head projection weights per block or packed matrices; choose one exact layout.

Recommendation:
	•	packed matrices for software/hardware alignment

Shapes:
	•	W_Q: [d_model, n_heads * d_head]
	•	W_K: [d_model, n_heads * d_head]
	•	W_V: [d_model, n_heads * d_head]
	•	W_O: [n_heads * d_head, d_model]

Biases:
	•	For first pass: no biases anywhere
	•	This simplifies both hardware and serialization

Reshape semantics

After projection:
	•	Q, K, V shape: [seq_len, n_heads, d_head]

Transpose for attention:
	•	[n_heads, seq_len, d_head]

Attention scores

For each head:
	•	scores = Q @ K^T
	•	Shape: [seq_len, seq_len]

Scale:
	•	multiply by 1/sqrt(d_head)

Mask

Use strict causal mask
	•	positions j > i are masked

For fixed-point hardware simplicity:
	•	define masked logits as a fixed minimum sentinel value before softmax

Softmax

Need exact definition.

Recommendation for Phase 1/2:
	•	implement reference softmax in Rust
	•	implement same approximate softmax in Verilog only if approximation is formally specified

Safer route:
	•	keep Phase 2 at a “functional flexible hardware” level and permit a LUT-based exact-spec approximation, but the approximation itself must be specified

Softmax spec:
	1.	subtract row max
	2.	exponentiate
	3.	sum row
	4.	divide each term by row sum

If fixed-point:
	•	define:
	•	exp LUT input range
	•	LUT resolution
	•	accumulator width
	•	output quantization

FFN

Use standard 2-layer MLP:
	•	W1: [d_model, d_ff]
	•	activation
	•	W2: [d_ff, d_model]

Activation

Recommendation: ReLU
Not GELU.

Reason:
	•	much simpler in Verilog
	•	deterministic
	•	no approximation drama in early phases

So:
	•	ffn(x) = ReLU(x @ W1) @ W2

Layer normalization

LayerNorm is one of the biggest cross-implementation traps.

Recommendation:
	•	affine LayerNorm with learned gamma, beta
	•	normalize across d_model

Shapes:
	•	gamma: [d_model]
	•	beta: [d_model]

Definition:
For each token vector x[t, :]:

mean = sum(x_i) / d_model
var = sum((x_i - mean)^2) / d_model
y_i = ((x_i - mean) / sqrt(var + eps)) * gamma_i + beta_i

Need exact eps.

Recommendation:
	•	eps = 1e-5 for float reference
	•	if fixed-point, define corresponding encoded constant explicitly

If you want to reduce Phase 2 pain, you can instead use RMSNorm. That is a valid choice and much easier in hardware. But if the goal is “typical transformer,” LayerNorm is more canonical.

My recommendation:
	•	Phase 1/2A: RMSNorm if goal is proving software/hardware identity fast
	•	Phase 1/2B: LayerNorm if goal is canonical transformer fidelity

Given your stated experiment, I would actually choose RMSNorm first.

⸻

Numeric spec

This is the most important section.

You need one numeric contract.

Recommendation

Use two numeric modes:

Mode A: reference mode
	•	Rust only
	•	f32
	•	used to generate golden weights/outputs

Mode B: canonical implementation mode
	•	Rust and Verilog
	•	fixed-point everywhere except token IDs
	•	this is the real comparison target

Fixed-point recommendation

Start with:
	•	Q8.8 or Q4.12 for activations and weights
	•	accumulators widened explicitly

Safer choice:
	•	weights/activations: signed 16-bit fixed-point
	•	accumulator: signed 32-bit
	•	post-matmul requantization rule explicitly specified

Example:
	•	storage: int16
	•	real value = stored / 2^FRAC_BITS

Choose:
	•	FRAC_BITS = 8 or 12

I would use:
	•	Q4.12 if dynamic range is manageable
	•	else Q8.8

Rounding

Specify exactly:
	•	round-to-nearest-even, or
	•	round-half-up, or
	•	truncate toward zero

Do not leave this ambiguous.

Recommendation:
	•	round half away from zero or truncate toward zero
	•	simplest hardware path is truncation, but document it

Saturation

Specify:
	•	saturating arithmetic on narrowing
	•	accumulator overflow behavior

Recommendation:
	•	accumulators widened enough to avoid overflow in baseline model
	•	saturation only on narrowing writes

⸻

Weight layout and serialization

Need one exact portable format.

Phase 1/2 weight file format

Use a simple binary container plus JSON metadata, or a single deterministic JSON for very small models.

Recommendation:
	•	model_spec.json
	•	weights.bin

model_spec.json

Contains:
	•	version
	•	architecture params
	•	numeric format
	•	tensor names
	•	tensor shapes
	•	tensor offsets in weights.bin
	•	tensor dtypes
	•	quantization scale / frac bits
	•	endianness

weights.bin

Flat binary blob.

Tensor storage order

Use row-major and define it explicitly:
	•	last dimension contiguous

Example:
	•	tensor [A, B, C]
	•	storage index = ((a * B) + b) * C + c

This must be identical in Rust and Verilog ROM loading.

Canonical tensor list

Example order:
	1.	tok_embedding
	2.	pos_embedding
	3.	layer0.norm1.gamma
	4.	layer0.norm1.beta
	5.	layer0.wq
	6.	layer0.wk
	7.	layer0.wv
	8.	layer0.wo
	9.	layer0.norm2.gamma
	10.	layer0.norm2.beta
	11.	layer0.w1
	12.	layer0.w2
	13.	final_norm.gamma
	14.	final_norm.beta
	15.	lm_head

Even if some are omitted initially, the list/order must be canonical.

⸻

Initialization spec

Need deterministic init even if later you import weights.

Recommendation

For early testing, use one of two options:

Option 1: deterministic synthetic weights

Best for bring-up.

Examples:
	•	small integer ramps
	•	hash-derived pseudo-random values with fixed seed
	•	sinusoidal fill

This is best for debugging.

Option 2: Xavier-like seeded init

More realistic, less debuggable.

Recommendation:
	•	use deterministic synthetic weights first
	•	then support imported trained weights later

Example deterministic init:

value(i) = ((i * 17 + 23) mod 256 - 128) / 256

Then quantize.

This lets both Rust and Verilog independently regenerate weights for sanity testing.

⸻

Inference path spec

Define exact top-level forward:

Top-level pipeline
	1.	read token IDs
	2.	lookup token embeddings
	3.	add positional embeddings
	4.	run 1 transformer block
	5.	optional final norm
	6.	output logits via LM head

Final norm

Recommendation:
	•	include final norm if you want closer transformer structure
	•	omit if you want simpler first pass

LM head

Shape:
	•	[d_model, vocab_size]

Output:
	•	logits [seq_len, vocab_size]

For simplest validation:
	•	compare full logits tensor
	•	also compare argmax token per position

⸻

Exact comparison policy

Need to define what “identical” means.

For reference float mode
	•	compare numerically with tolerance

For canonical fixed-point mode
	•	compare bit-exact outputs
	•	no tolerance

Required golden checks:
	1.	embedding output
	2.	norm output
	3.	Q/K/V projections
	4.	attention score matrix pre-mask
	5.	attention weights post-softmax
	6.	attention output
	7.	FFN hidden activation
	8.	block output
	9.	final logits

Bit-exact intermediate checkpoints are critical.

⸻

Phase 1 spec: Rust reference implementation

Goal

Implement the canonical transformer spec in Rust, with:
	•	reference f32 mode
	•	canonical fixed-point mode
	•	deterministic weight loading
	•	golden vector dumping

Deliverables
	1.	spec/transformer_v1.md
	2.	spec/model_spec.json
	3.	Rust crate:
	•	tensor ops
	•	fixed-point ops
	•	embedding
	•	norm
	•	attention
	•	ffn
	•	model top-level
	4.	test harness
	5.	golden output generator

Required modules
	•	types.rs
	•	fixed.rs
	•	tensor.rs
	•	embedding.rs
	•	norm.rs
	•	attention.rs
	•	ffn.rs
	•	model.rs
	•	weights.rs
	•	golden.rs

Required capabilities
	•	load weights.bin
	•	run one forward pass
	•	dump intermediate tensors
	•	serialize golden vectors
	•	run reference and canonical mode

Rust acceptance criteria
	•	same input always produces same output
	•	fixed-point path is deterministic
	•	all intermediate tensor dumps stable
	•	golden vectors generated for at least 3 test token sequences
	•	unit tests for every operator

⸻

Phase 2 spec: Verilog flexible hardware implementation

Goal

Implement the same transformer spec in Verilog with mutable/external weights, not frozen constants yet.

This is the flexible hardware baseline.

Scope

Single-batch inference only.
No training.
No dynamic reconfiguration beyond loading weights/memory contents.

Architectural intent

Do not try to optimize aggressively yet.
Goal is semantic fidelity.

External interfaces

Need explicit interfaces for:
	•	token input memory
	•	weight memory / ROM / preload mechanism
	•	output logits memory
	•	control signals: start/done/reset

Suggested decomposition

Modules:
	•	embedding_lookup
	•	pos_add
	•	norm
	•	linear
	•	qkv_project
	•	attention_core
	•	softmax_core
	•	ffn_core
	•	transformer_block
	•	top

Memory model

Weights initially stored in:
	•	BRAM init files, or
	•	external preloadable RAM blocks

The key point is:
	•	weights are not structurally compiled into logic yet

Control model

Use a simple FSM:
	1.	idle
	2.	load/prepare
	3.	embedding
	4.	norm1
	5.	qkv
	6.	attn scores
	7.	mask
	8.	softmax
	9.	weighted sum
	10.	output projection
	11.	residual
	12.	norm2
	13.	ffn1
	14.	relu
	15.	ffn2
	16.	residual
	17.	final projection
	18.	done

No streaming complexity initially unless needed.

Numeric behavior

Must exactly match canonical fixed-point Rust mode:
	•	same fixed-point widths
	•	same rounding
	•	same saturation
	•	same LUT definitions for exp/sqrt if used
	•	same mask sentinel

Verilog acceptance criteria
	•	bit-exact match with Rust canonical fixed-point outputs
	•	bit-exact match at intermediate checkpoints
	•	passes simulation for all golden test vectors
	•	synthesizes successfully
	•	area/timing reports generated

⸻

Shared artifacts between Phase 1 and 2

These are mandatory:

1. Canonical spec doc

spec/transformer_v1.md

2. Machine-readable shape/numeric spec

spec/model_spec.json

3. Canonical test vectors
	•	tests/input_000.bin
	•	tests/output_logits_000.bin
	•	intermediate dumps

4. Weight blob
	•	weights/weights_v1.bin

5. LUT definitions

If using approximations:
	•	exp LUT
	•	inverse sqrt LUT
	•	any requant tables

These must be shared artifacts, not reimplemented ad hoc.

⸻

Questions you should lock before coding

You identified the right ones. These must be frozen up front:
	1.	Numerics
	•	float reference only, or fixed-point canonical?
	•	Q format?
	•	rounding?
	•	saturation?
	2.	Norm
	•	LayerNorm or RMSNorm?
	3.	Positional encoding
	•	learned absolute, sinusoidal, or RoPE?
	4.	Attention
	•	standard MHA only?
	•	causal only?
	•	no KV cache yet?
	5.	Biases
	•	none, or included?
	6.	Activation
	•	ReLU or GELU?
	7.	Weight format
	•	binary blob + json metadata?
	8.	Comparison criterion
	•	bit-exact at all intermediates?

⸻

My recommended concrete v1 choices

For fastest path to a valid experiment:
	•	1 layer
	•	d_model = 32
	•	n_heads = 2
	•	seq_len = 16
	•	learned absolute positional embeddings
	•	RMSNorm
	•	causal MHA
	•	ReLU FFN
	•	no biases
	•	Q8.8 or Q4.12 fixed-point canonical mode
	•	row-major binary weight blob
	•	bit-exact intermediate comparisons

This is slightly less “typical modern LLM” than RoPE+GELU+RMSNorm, but much better for software/hardware identity.

If you want closer-to-modern while still sane:
	•	RMSNorm
	•	RoPE
	•	SiLU/GELU
	•	still no bias

But that is a harder first experiment.

⸻

Bottom line

For Phase 1 and 2, the actual deliverable is not just code. It is:

a single canonical transformer contract
that both Rust and Verilog can execute identically.

If that contract is tight, Phase 3 becomes meaningful:
	•	same semantics
	•	flexible hardware vs frozen hardware
	•	real synthesis comparison

If you want, next I can turn this into a repo-ready spec document with:
	•	exact JSON schema
	•	exact tensor list
	•	exact fixed-point rules
	•	exact checkpoint names.

