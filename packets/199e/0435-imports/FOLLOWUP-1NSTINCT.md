Fix requests, not accepted rejects or product acceptance. Continue from the isolated return branches below, preserving ordinary finite behavior.

A24 6cb87d05609381ade197133a186630c4f365f974: finite greatestFiniteMagnitude level/dt0.016 makes derived variance infinite; opposite-huge then NaN, axis about1.15e215 and persists out of range after ordinary0.4 input. Add overflow-safe derived-state handling with regression for state recovery, invalid sample holds and ordinary goldens, compiling semantic mutants in both modes. Do not silently clamp or change established valid behavior without documenting the choice.

A25 3aef37d69449a3ad6ccff120d74439eea80d520c: leadingFrames with finite greatestFiniteMagnitude left and width, ink0/gap0 returns finite origin/width but maxX infinity. Check width-derived rectangle bounds as well as ink advance; add both leading/trailing overflow controls and finite geometry goldens. Return source patch plus exact tests and raw Swift modes.

Independent evidence: 0435-imports/LINUX-REPORT.md and packet SHA376f4193a88eebbf1b0417b079051b19553f1ac009914bbfd695d518f5b62465. These two requests are not additional startable-stock packets until full inline fixtures are supplied.
