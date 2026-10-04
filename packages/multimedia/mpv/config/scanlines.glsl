//!HOOK OUTPUT
//!BIND HOOKED
//!DESC Scanlines: every second panel line dimmed

// Runs on the finished picture at panel resolution, so the lines are the
// panel's own rows. A 480-line DVD scaled to the 960-line panel is exactly
// two rows per source line: one at full brightness, one dimmed, which is
// about what a TV of the time drew.
vec4 hook()
{
    vec4 color = HOOKED_tex(HOOKED_pos);
    float row = floor(HOOKED_pos.y * HOOKED_size.y);
    if (mod(row, 2.0) >= 1.0)
        color.rgb *= 0.55;
    return color;
}
