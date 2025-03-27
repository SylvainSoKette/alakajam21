#version 330

in vec2 fragTexCoord;

uniform sampler2D sScreenTexture;
uniform vec2 uResolution;
uniform float uBrightness;

const float curvature = 5.0;
const float scanlineIntensity = 1.2;
const float rgbShift = 0.0015;

// https://babylonjs.medium.com/retro-crt-shader-a-post-processing-effect-study-1cb3f783afbc
vec2 curveRemapUV(vec2 uv) {
	uv = uv * 2.0 - 1.0;
	vec2 offset = abs(uv.yx) / vec2(curvature, curvature);
	uv = uv + uv * offset * offset;
	uv = uv * 0.5 + 0.5;
	return uv;
}

void main()
{
	vec2 uv = gl_FragCoord.xy / uResolution.xy;
	uv = curveRemapUV(uv);
	// RGB shift
	vec2 rUV = uv + vec2(rgbShift, 0.0);
	vec2 gUV = uv;
	vec2 bUV = uv - vec2(rgbShift, 0.0);
	// final color
	vec3 color;
	color.r = texture2D(sScreenTexture, rUV).r;
	color.g = texture2D(sScreenTexture, gUV).g;
	color.b = texture2D(sScreenTexture, bUV).b;
	// scanlines
	float scanline = sin(uv.y * uResolution.y * 2.0) * 0.5 + 0.5;
	color *= 1.0 - scanlineIntensity + scanline * scanlineIntensity;
	// vignette effect
	float vignette = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
	vignette = pow(vignette, 0.25);
	color *= vignette;
	// apply brightness
	color *= uBrightness;
	gl_FragColor = vec4(color, 1.0);
}
