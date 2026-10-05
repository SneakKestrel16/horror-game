// The farm's sky: a gradient with a sunset glow and the earth's shadow
// opposite it, a sun, a moon, stars with a faint Milky Way, and drifting
// clouds. Looks.Daylight sets every uniform for the time of day; nothing here
// reads TIME, so the radiance cubemap is only redrawn when they change.
shader_type sky;

uniform vec3 zenith_color : source_color;
uniform vec3 horizon_color : source_color;  // Also the fog colour, so far ground meets the sky.
uniform vec3 glow_color : source_color;  // Low in the sky around the sun, strongest when it is low.
uniform vec3 shadow_color : source_color;  // Low in the sky opposite the sun.
uniform vec3 sun_color : source_color;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);  // Toward the sun.
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);  // Toward the moon.
uniform float moon_visible : hint_range(0.0, 1.0) = 0.0;
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float star_turn = 0.0;  // Radians the stars have turned about the pole.
uniform float twinkle = 0.0;  // Seconds, for twinkling.
uniform vec3 cloud_lit : source_color;
uniform vec3 cloud_shade : source_color;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.4;
uniform vec2 cloud_drift = vec2(0.0);

const float SUN_RADIUS = 0.022;  // Radians; the real sun is 0.0047, but it reads better bigger.
const float MOON_RADIUS = 0.03;
const vec3 POLE = vec3(0.0, 0.62, -0.78);  // The stars turn about this (north, about 38 degrees up).

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 0.0));
	float b = hash(vec3(i + vec2(1.0, 0.0), 0.0));
	float c = hash(vec3(i + vec2(0.0, 1.0), 0.0));
	float d = hash(vec3(i + vec2(1.0, 1.0), 0.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		total += amplitude * noise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p;
		amplitude *= 0.5;
	}
	return total;
}

// Rotates v about a unit axis by angle (Rodrigues).
vec3 turn(vec3 v, vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

vec3 starfield(vec3 dir) {
	vec3 p = turn(dir, POLE, star_turn) * 140.0;
	vec3 cell = floor(p);
	float pick = hash(cell);
	vec3 light = vec3(0.0);
	if (pick > 0.93) {
		vec3 offset = vec3(hash(cell + 11.0), hash(cell + 23.0), hash(cell + 37.0)) - 0.5;
		float d = length(fract(p) - 0.5 - offset * 0.5);
		float bright = pow((pick - 0.93) / 0.07, 3.0) * 2.5 + 0.15;
		float flicker = 0.75 + 0.25 * sin(twinkle * (2.0 + 5.0 * hash(cell + 5.0)) + pick * 60.0);
		vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.88, 0.75), hash(cell + 51.0));
		light = tint * bright * flicker * smoothstep(0.22, 0.0, d);
	}
	// A faint Milky Way: a soft band of mottled light across the sky.
	vec3 band = turn(dir, POLE, star_turn);
	float across = dot(band, normalize(vec3(0.85, 0.2, 0.5)));
	float milky = exp(-across * across * 25.0) * smoothstep(0.35, 0.8, fbm(band.xz * 14.0 + band.y * 6.0));
	light += vec3(0.6, 0.65, 0.85) * milky * 0.035;
	return light;
}

// The moon's face, its halo, and how far the disc covers this pixel.
vec4 moon(vec3 dir) {
	float facing = dot(dir, moon_dir);
	float angle = acos(clamp(facing, -1.0, 1.0));
	vec3 tint = vec3(0.75, 0.8, 0.95);
	vec3 halo = tint * (pow(max(facing, 0.0), 2500.0) * 0.5 + pow(max(facing, 0.0), 60.0) * 0.05);
	float disc = smoothstep(MOON_RADIUS, MOON_RADIUS * 0.9, angle);
	if (disc <= 0.0) {
		return vec4(halo, 0.0);
	}
	vec3 right = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, moon_dir);
	vec2 q = vec2(dot(dir, right), dot(dir, up)) / sin(MOON_RADIUS);
	float maria = smoothstep(0.45, 0.7, fbm(q * 2.2 + 3.0));
	float rim = sqrt(max(1.0 - dot(q, q), 0.0));
	vec3 face = vec3(1.0, 0.97, 0.9) * mix(1.0, 0.62, maria) * (0.55 + 0.45 * rim) * 1.1;
	return vec4(halo + face, disc);
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	float up = clamp(h, 0.0, 1.0);
	float toward_sun = dot(dir, sun_dir);
	float low = pow(1.0 - up, 3.0);
	float sun_low = 1.0 - smoothstep(0.0, 0.5, sun_dir.y);  // 1 near the horizon, 0 high up.

	vec3 color = mix(horizon_color, zenith_color, pow(up, 0.5));
	// The bright band round the sun, wider and stronger as the sun sinks.
	float glow = pow(max(toward_sun * 0.5 + 0.5, 0.0), mix(6.0, 3.0, sun_low));
	color = mix(color, glow_color, clamp(glow * low * (0.35 + 0.65 * sun_low), 0.0, 1.0));
	// The earth's shadow rising opposite a low sun.
	float away = pow(max(-toward_sun * 0.5 + 0.5, 0.0), 3.0);
	color = mix(color, shadow_color, clamp(away * low * sun_low, 0.0, 1.0));
	// A haze round the sun itself.
	float sun_up = smoothstep(-0.12, 0.02, sun_dir.y);
	color += sun_color * (pow(max(toward_sun, 0.0), 200.0) * 0.6 + pow(max(toward_sun, 0.0), 12.0) * 0.12) * sun_up;

	if (!AT_CUBEMAP_PASS) {
		color += starfield(dir) * stars * smoothstep(0.0, 0.3, h);
	}
	vec4 m = moon(dir);
	color += m.rgb * moon_visible * (AT_CUBEMAP_PASS ? 1.0 - m.a : 1.0);
	if (!AT_CUBEMAP_PASS) {
		float disc = smoothstep(SUN_RADIUS, SUN_RADIUS * 0.85, acos(clamp(toward_sun, -1.0, 1.0)));
		color = mix(color, sun_color * 6.0, disc * sun_up);
	}

	// Clouds on a flat ceiling, thinning toward the horizon.
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.15) * 0.8 + cloud_drift;
		float n = fbm(uv);
		float density = smoothstep(0.62 - cloud_cover * 0.3, 0.85 - cloud_cover * 0.3, n);
		density *= smoothstep(0.0, 0.18, h);
		if (density > 0.0) {
			// Lit where the cloud thins toward the sun, as if light came through.
			float behind = fbm(uv + normalize(sun_dir.xz + vec2(0.0001)) * 0.15);
			float lit = clamp(0.55 + (n - behind) * 4.0, 0.0, 1.0);
			vec3 cloud = mix(cloud_shade, cloud_lit, lit);
			cloud += sun_color * pow(max(toward_sun, 0.0), 8.0) * (1.0 - density) * 0.8 * sun_up;
			cloud += vec3(0.5, 0.55, 0.7) * pow(max(dot(dir, moon_dir), 0.0), 25.0) * moon_visible * 0.12;
			color = mix(color, cloud, density * 0.92);
		}
	}

	// Below the horizon, the ground fades to dark.
	color = mix(color, horizon_color * 0.35, smoothstep(0.0, -0.2, h));
	COLOR = color;
}
