    float adapt = amount;
    adapt *= 1.0 + 0.8 * (1.0 - peak);
    adapt *= 1.0 - smoothstep(0.05, 0.35, noise) * 0.5;
    adapt *= mix(0.80, 1.20, motion);
    float is_hdr = step(1.0, max(max(color.r, color.g), color.b));
    adapt *= mix(1.0, 0.55, is_hdr);
    luma_gain *= hdr_black_gate(luma, is_hdr);

