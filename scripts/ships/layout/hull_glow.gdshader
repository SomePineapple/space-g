shader_type canvas_item;

// Multiplies a module's emissive layer past white so the region's
// WorldEnvironment glow actually catches it, and breathes it slowly in and out
// (see HullGlowLayer).
//
// The gain CANNOT be applied as a vertex colour. Godot stores an ArrayMesh's
// ARRAY_COLOR as 8-bit unorm, so any Color above 1.0 silently clamps to white on
// the way into the mesh — the hull renderer spent a long time multiplying its
// lights by 1.7 and getting exactly the same pixels it would have got from 1.0.
// A shader uniform is a float all the way to the fragment, and with
// rendering/viewport/hdr_2d on, the RGBA16F canvas buffer keeps what it writes.
//
// The pulse is driven from TIME rather than animated from GDScript so it costs
// no per-frame CPU at all, which is the standing rule for anything that runs per
// hull per frame (docs/performance.md).

// TAU is a built-in in Godot's shading language — declaring one here is a
// redefinition error, and a shader that fails to compile falls back silently to
// unlit drawing rather than announcing itself in-game.

uniform float gain : hint_range(1.0, 16.0) = 1.0;
// How far the lamp dims at the bottom of its cycle, as a fraction of gain. The
// trough still has to clear the glow threshold of 1.0 or the lights stop being
// lights for half of every cycle.
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_period = 5.0;
// Per-hull offset so ships nearby do not breathe in lockstep, which reads as the
// whole scene blinking rather than as each ship idling.
uniform float phase = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float wave = 0.5 + 0.5 * sin(TIME * TAU / pulse_period + phase);
	float level = gain * (1.0 - pulse_depth * (1.0 - wave));
	// Alpha is left alone: it decides where the lamp is, and scaling it would
	// spread the lamp rather than brighten it.
	COLOR = vec4(source.rgb * level, source.a);
}
