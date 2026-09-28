#version 450

// A consumer-TV look for a core that renders above native resolution.
//
// SwanStation upscales 4x, so the image this receives is already 960 lines:
// a CRT shader that counts its input lines would put a "scanline" on every
// panel row. This one draws a beam per console line over the upscaled
// picture, keeping the detail the upscale gives. UPSCALE says how many
// source lines make one console line (4 for SwanStation at 4x), so a
// 224-line game gets 224 beams and a 240-line game 240; with UPSCALE at 0
// the LINES parameter is used instead.
//
// At UPSCALE 1 the source is the console's own 320x240. Sampling it
// where the panel pixel
// falls would then be a bilinear blow-up, four panel pixels wide: blur, not
// a beam. So at 1 every read snaps to the centre of a console pixel, and
// the horizontal spread reaches the neighbour only from the outer half of
// each pixel. crt-240-1x.slangp is this shader with UPSCALE at 1.
//
// In linear light:
//   beam   a gaussian across each console line, wider for brighter colour,
//          which is how a real beam spot behaves
//   soft   a little horizontal spread, as a beam has
//   glow   a touch of the neighbouring lines added back
//   mask   an aperture grille, one output pixel per phosphor stripe
//   boost  brings the average back up, which an OLED can afford
// One pass, nine texture reads a pixel.

layout(push_constant) uniform Push
{
	vec4 SourceSize;
	vec4 OutputSize;
	float UPSCALE;
	float LINES;
	float BEAM_MIN;
	float BEAM_MAX;
	float SOFT;
	float GLOW;
	float MASK;
	float BOOST;
} params;

#pragma parameter UPSCALE "Source lines per console line (0: use LINES)" 4.0 0.0 8.0 1.0
#pragma parameter LINES "Console lines per frame, when UPSCALE is 0" 240.0 120.0 1080.0 1.0
#pragma parameter BEAM_MIN "Beam width, dark" 0.20 0.05 0.60 0.01
#pragma parameter BEAM_MAX "Beam width, bright" 0.36 0.05 0.80 0.01
#pragma parameter SOFT "Horizontal softness" 0.35 0.0 1.0 0.05
#pragma parameter GLOW "Glow" 0.10 0.0 0.5 0.01
#pragma parameter MASK "Mask strength" 0.25 0.0 1.0 0.05
#pragma parameter BOOST "Brightness boost" 1.30 1.0 2.0 0.05

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
	gl_Position = global.MVP * Position;
	vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

vec3 lin(vec2 uv)
{
	vec3 c = texture(Source, uv).rgb;
	return c * c;                       /* close enough to 2.2, and cheap */
}

void main()
{
	float lines = params.UPSCALE > 0.5 ? params.SourceSize.y / params.UPSCALE
	                                   : params.LINES;
	float line_h = 1.0 / lines;         /* one console line, in uv */

	/* Where in its console line this pixel is: -0.5 top, 0 centre, 0.5 bottom. */
	float ly = vTexCoord.y * lines;
	float d = fract(ly) - 0.5;
	/* The source says how many console pixels it has when UPSCALE is
	 * known; otherwise 4:3 over the lines makes it LINES * 4/3 across. */
	float cols = params.UPSCALE > 0.5 ? params.SourceSize.x / params.UPSCALE
	                                  : lines * 4.0 / 3.0;
	bool native = params.UPSCALE > 0.5 && params.UPSCALE < 1.5;

	/* This pixel's own colour. Above 1x it is read where it is rather than
	 * at the line's centre: the upscale's vertical detail stays and the
	 * beam only shapes it. At 1x it is the console pixel this falls in. */
	vec2 uv = native ? (floor(vTexCoord * vec2(cols, lines)) + 0.5) / vec2(cols, lines)
	                 : vTexCoord;
	/* The neighbouring lines' colour, at their centres. */
	vec2 centre = vec2(uv.x, (floor(ly) + 0.5) * line_h);

	/* Horizontal spread of half a console pixel either side. At 1x the
	 * half-pixel step snaps to the neighbour from the outer half of a
	 * pixel and to the pixel itself from the inner half, so the centre
	 * stays sharp and only the edges soften. */
	vec2 hx = vec2(0.5 / cols, 0.0);
	vec2 l = native ? (floor((vTexCoord - hx) * vec2(cols, lines)) + 0.5) / vec2(cols, lines)
	                : uv - hx;
	vec2 r = native ? (floor((vTexCoord + hx) * vec2(cols, lines)) + 0.5) / vec2(cols, lines)
	                : uv + hx;
	vec3 c = lin(uv) * (1.0 - params.SOFT)
	       + (lin(l) + lin(r)) * (0.5 * params.SOFT);

	/* The beam: a gaussian across the line, its width following brightness. */
	vec3 w = mix(vec3(params.BEAM_MIN), vec3(params.BEAM_MAX), sqrt(c));
	vec3 beam = exp(-(d * d) / (2.0 * w * w));
	vec3 col = c * beam;

	/* The next line's beam reaches into this one, and the one before it. */
	vec2 up = vec2(0.0, line_h), dn = vec2(0.0, -line_h);
	vec3 cu = lin(centre + up), cd = lin(centre + dn);
	vec3 wu = mix(vec3(params.BEAM_MIN), vec3(params.BEAM_MAX), sqrt(cu));
	vec3 wd = mix(vec3(params.BEAM_MIN), vec3(params.BEAM_MAX), sqrt(cd));
	col += cu * exp(-((d - 1.0) * (d - 1.0)) / (2.0 * wu * wu));
	col += cd * exp(-((d + 1.0) * (d + 1.0)) / (2.0 * wd * wd));

	/* Glow: a little of the surroundings, added back. */
	vec3 around = (lin(centre + up + hx) + lin(centre + dn - hx) +
	               lin(centre + up - hx) + lin(centre + dn + hx)) * 0.25;
	col += around * params.GLOW;

	/* Aperture grille: R, G, B stripes, one output pixel each. */
	float stripe = mod(floor(vTexCoord.x * params.OutputSize.x), 3.0);
	vec3 mask = vec3(1.0 - params.MASK);
	if (stripe < 1.0)      mask.r = 1.0;
	else if (stripe < 2.0) mask.g = 1.0;
	else                   mask.b = 1.0;
	col *= mask;

	col *= params.BOOST;
	FragColor = vec4(sqrt(clamp(col, 0.0, 1.0)), 1.0);
}
