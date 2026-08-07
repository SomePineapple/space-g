shader_type canvas_item;
render_mode blend_mix, unshaded;

// Drives the per-star flicker entirely on the GPU so a starfield layer needs no
// per-frame _process or queue_redraw on the CPU. Each star's parameters arrive
// as MultiMesh per-instance custom data (see starfield_layer.gd):
//   x = flicker speed (rad/s)
//   y = phase offset
//   z = flicker strength (0.0 for a steady star, which makes dip == 1.0 and
//       leaves colour and size untouched — so steady and flickering stars can
//       share one MultiMesh, and therefore one draw call)

void vertex() {
	float pulse = (sin(TIME * INSTANCE_CUSTOM.x + INSTANCE_CUSTOM.y) + 1.0) * 0.5;
	float dip = 1.0 - INSTANCE_CUSTOM.z * pulse;
	COLOR.rgb *= dip;
	// Stars shrink slightly as they dim, matching the old CPU flicker.
	VERTEX *= mix(0.6, 1.0, dip);
}

void fragment() {
	// The instance quad is rasterised as an antialiased disc so stars keep the
	// round look they had when they were draw_circle() calls.
	COLOR.a *= 1.0 - smoothstep(0.35, 0.5, length(UV - vec2(0.5)));
}
