#version 330

in vec2 fragTexCoord;

out vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

void main()
{
    vec2 screenRes = vec2(1280, 720);
    vec2 pixel = 1.0f / screenRes;

    vec4 color = texture(texture0, fragTexCoord);
    // clearly show pixels
    float v = float(int(fragTexCoord.y * screenRes.y) % 4 != 0);
    float h = float(int(fragTexCoord.x * screenRes.x) % 4 != 0);
    color.r *= v * h;
    color.g *= v * h;
    color.b *= v * h;
    // bleed pixels
    int passes = 4;
    vec2 topLeft =     vec2(-pixel.x, -pixel.y);
    vec2 topRight =    vec2( pixel.x, -pixel.y);
    vec2 bottomLeft =  vec2(-pixel.x,  pixel.y);
    vec2 bottomRight = vec2( pixel.x,  pixel.y);
    for (int i = 1; i < passes; i++) {
        float d = 0.5 * i;
        color += texture(texture0, fragTexCoord + d * topLeft);
        color += texture(texture0, fragTexCoord + d * topRight);
        color += texture(texture0, fragTexCoord + d * bottomLeft);
        color += texture(texture0, fragTexCoord + d * bottomRight);
    }
    // attenuate color after accumulation
    color /= (passes * 3.1415);

    fragColor = color;
}
