use kni_core::tolerance::*;
fn main(){ for f in std::env::args().skip(1){ let t=derive_from_png(&std::fs::read(&f).unwrap()).unwrap(); println!("{} eps_px={:.4} var_px2={:.5} t_line_px={:.4} crossings={} step_frac={:.3} stair={:.4}",f.rsplit('/').next().unwrap(),t.rdp_eps_px,t.fit_variance_px2,t.t_line_px,t.crossings,t.step_fraction,t.stair_rms_px);} }
