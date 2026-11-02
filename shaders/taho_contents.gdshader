shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Contents of the cup: white tofu with arnibal marbled through it.
//
// Uses object-space XZ rather than UV so it reads correctly on both the top
// face and the sides of a cylinder without needing custom UVs.

uniform vec3 tofu_color : source_color = vec3(0.964, 0.945, 0.898);
uniform vec3 arnibal_color : source_color = vec3(0.329, 0.157, 0.043);
uniform float radius = 0.37;

// 0..1 how much syrup is in the cup.
uniform float arnibal_amount : hint_range(0.0, 1.0) = 0.0;
// 0..~1.2 how thoroughly it has been swirled. Past ~1.0 it goes flat brown.
uniform float mix_amount : hint_range(0.0, 1.5) = 0.0;

// How many separate sheets of tofu were laid in. Taho is shaved in thin
// layers, and the stack of them is the most recognisable image of the stuff,
// so the sides are banded to show it. Swirling blurs the bands away, because
// by then it is no longer a stack.
uniform float sheets = 0.0;
uniform float cup_height = 0.28;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec2 p = obj_pos.xz / radius;
	float r = clamp(length(p), 0.0, 1.0);
	float a = atan(p.y, p.x);

	// Unmixed: syrup pools in the middle as a dark blob.
	float pool = 1.0 - smoothstep(arnibal_amount * 0.75, arnibal_amount * 0.95, r);

	// Mixing drags that pool into spiral arms.
	float spiral = sin(a * 3.0 + r * 9.0 - mix_amount * 14.0);
	float arms = smoothstep(0.1, 0.9, spiral) * arnibal_amount;

	float marbled = mix(pool, arms, smoothstep(0.0, 0.45, mix_amount));

	// Over-mixing flattens everything toward a uniform, duller brown.
	float flat_mix = smoothstep(0.7, 1.15, mix_amount);
	float f = mix(marbled, arnibal_amount * 0.85, flat_mix);

	vec3 albedo = mix(tofu_color, arnibal_color, clamp(f, 0.0, 1.0));

	if (sheets > 0.5) {
		float up = obj_pos.y / cup_height + 0.5;
		float band = abs(fract(up * sheets) - 0.5) * 2.0;
		// Only the seam between sheets darkens, and only on the sides — the
		// top of the cup is one continuous surface.
		float seam = (1.0 - smoothstep(0.0, 0.35, band)) * smoothstep(0.55, 0.95, r);
		albedo *= 1.0 - 0.16 * seam * (1.0 - smoothstep(0.0, 0.6, mix_amount));
	}

	ALBEDO = albedo;
	ROUGHNESS = mix(0.55, 0.8, f);
}
