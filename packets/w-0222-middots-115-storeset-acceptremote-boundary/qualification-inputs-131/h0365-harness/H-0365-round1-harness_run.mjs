import { spawnSync } from 'node:child_process';
let bad=0; for (const c of ['control_ok','T2_rev_denied','T3_base_denied','T4_silent_drop_synthetic','T5_get_throws_negative_control','T6_replay']) {
  const p = spawnSync('node',['case.mjs',c],{encoding:'utf8'}); process.stdout.write(p.status===0?p.stdout:`FAIL ${c}\n${p.stderr}`); if(p.status) bad++; }
process.exit(bad?1:0);
