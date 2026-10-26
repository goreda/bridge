//! Explicit resource/policy/frame caller. Output descriptive only.
use kni_core::{capture::capture_gray,capture_dispatch::decode_source,jpeg_source::Limits,tolerance::derive_from_gray,cubic_fit::FitPolicy};
fn main()->Result<(),String>{
 let a:Vec<String>=std::env::args().collect();
 if a.len()!=10{return Err("usage: dispatch_fit INPUT SCALE EPS_OR_DERIVED SE_OR_DERIVED REFITS MAX_INPUT_BYTES MAX_PIXELS MAX_WORKING_BYTES OUTPUT".into());}
 let scale:f64=a[2].parse().map_err(|_|"invalid scale")?;
 if !scale.is_finite()||scale<=0.0{return Err("invalid frame scale".into());}
 let limits=Limits{max_input_bytes:a[6].parse().map_err(|_|"invalid input limit")?,max_pixels:a[7].parse().map_err(|_|"invalid pixel limit")?,max_working_bytes:a[8].parse().map_err(|_|"invalid working limit")?};
 let bytes=std::fs::read(&a[1]).map_err(|e|e.to_string())?;
 let d=decode_source(&bytes,&kni_core::capture::DecodeLimits{max_input_bytes:limits.max_input_bytes,max_pixels:limits.max_pixels,max_working_bytes:limits.max_working_bytes},limits).map_err(|e|format!("{:?}",e))?;
 let derived=derive_from_gray(d.width,d.height,&d.gray)?;
 let eps=if a[3]=="derived"{derived.rdp_eps_px}else{a[3].parse().map_err(|_|"invalid eps")?};
 let se=if a[4]=="derived"{derived.fit_se_scaled(scale)}else{a[4].parse().map_err(|_|"invalid squared error")?};
 if !eps.is_finite()||eps<0.0||!se.is_finite()||se<=0.0{return Err("invalid fit/capture policy".into());}
 let policy=FitPolicy{squared_error:se,max_refits:a[5].parse().map_err(|_|"invalid refits")?};
 let mc=capture_gray(d.width,d.height,&d.gray,eps)?;
 let drawing=kni_core::generated_draw::fit_from_source(&mc,&d.gray,scale,&policy)?;
 let(rings,spans,fallback,dropped)=(drawing.rings,drawing.source_fit_spans,drawing.fallback,drawing.dropped);
 std::fs::write(&a[9],format!("DESCRIPTIVE_ONLY\nsource_receipt={:?}\nscale={}\neps={}\nse={}\nrefits={}\nderived={:?}\nrings={}\nspans={}\nfallback={}\ndropped={}\nsealed_membership=UNVERIFIED\nvector_gate=NOT_EVALUATED\nfixed_fitter_line_circle_controls=RETAINED_NOT_DERIVED\n",d.receipt,scale,eps,se,policy.max_refits,derived,rings.len(),spans,fallback,dropped)).map_err(|e|e.to_string())?;
 Ok(())
}
