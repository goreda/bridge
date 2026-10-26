//! Receipt runner. Every numeric parameter is a required argument; nothing is defaulted.
//! args: png expected_sha256 frame_id K threshold capture_eps flatten_steps fit_se fit_refits advance
use kni_core::{capture::capture_png,capture_fit::{fit_captured,fit_captured_with_economy},cubic_fit::FitPolicy,economy::*,economy_eval::*,reference_slice::DrawnGlyph};
fn main(){
 let a:Vec<String>=std::env::args().collect();
 if a.len()!=11 {eprintln!("need 10 args");std::process::exit(2);}
 let png=std::fs::read(&a[1]).unwrap();
 let cfg=EvalConfig{frame_id:a[3].clone(),scale_k:a[4].parse().unwrap(),threshold:a[5].parse().unwrap(),canvas:(1485,1050),capture_eps:a[6].parse().unwrap(),flatten_steps:a[7].parse().unwrap(),expected_source_sha256:a[2].clone(),advance:a[10].parse().unwrap(),render_limits:RenderLimits{max_pixels:1485*1050,max_flatten_steps:32,max_edges:1485*1050,max_working_bytes:1<<28}};
 let mut ev=match ProductionEvaluator::new(cfg.clone(),&png){Ok(e)=>e,Err(e)=>{println!("PIN_FAIL {e}");std::process::exit(3);}};
 let mc=capture_png(&png,cfg.capture_eps).unwrap();
 let pol=FitPolicy{squared_error:a[8].parse().unwrap(),max_refits:a[9].parse().unwrap()};
 let (br,..)=fit_captured(&mc.rings,cfg.scale_k,&pol);
 let (er,..)=fit_captured_with_economy(&mc.rings,cfg.scale_k,&pol);
 let b=DrawnGlyph{glyph_id:"g".into(),rings:br};let e=DrawnGlyph{glyph_id:"g".into(),rings:er};
 let bb=ev.final_font_bytes(&b);let eb=ev.final_font_bytes(&e);
 let ab=ev.assess(&b,&b);let ae=ev.assess(&b,&e);
 println!("source_sha={} font_bytes_base={:?} font_bytes_econ={:?} bytes_identical={}",sha256_hex(&png),bb.as_ref().map(|x|sha256_hex(x)),eb.as_ref().map(|x|sha256_hex(x)),bb==eb);
 println!("assess_base_self={:?}",ab);
 println!("assess_base_vs_econ={:?}",ae);
 println!("assessments_equal={}",format!("{:?}",ab)==format!("{:?}",ae));
}
