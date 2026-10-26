// Authorized fixed numeric replay, source-scan provenance attributed, no image extraction.
use kni_core::cubic_fit::{fit_run,adjacent_chord_tangents,FitPolicy,FitOutcome};
use kni_core::reference_slice::Point;
#[test]
fn numeric_packet_control_overshoot(){
 let samples=[Point{x:383.3903,y:92.2851},Point{x:150.0182,y:341.4266},Point{x:150.9631,y:342.6550},Point{x:190.7565,y:342.7242},Point{x:208.0580,y:344.0464}];
 let(left,right)=adjacent_chord_tangents(&samples).unwrap();
 println!("tangents {:?} {:?}",left,right);
 let result=fit_run(&samples,left,right,&FitPolicy{squared_error:1.,max_refits:6});
 match result{FitOutcome::Fitted{controls,parameters,max_squared_error}=>{
 println!("controls {:?}\nparameters {:?}\nmax_squared_error {:.15}",controls,parameters,max_squared_error);
 let xmin=samples.iter().map(|p|p.x).fold(f64::INFINITY,f64::min);let xmax=samples.iter().map(|p|p.x).fold(f64::NEG_INFINITY,f64::max);let ymin=samples.iter().map(|p|p.y).fold(f64::INFINITY,f64::min);let ymax=samples.iter().map(|p|p.y).fold(f64::NEG_INFINITY,f64::max);
 // Peer margin diagnostic only, not an engine policy/default.
 let margin=0.15*(xmax-xmin).max(ymax-ymin)+2.;
 let violations=controls.iter().enumerate().filter(|(_,p)|p.x<xmin-margin||p.x>xmax+margin||p.y<ymin-margin||p.y>ymax+margin).map(|(i,_)|i).collect::<Vec<_>>();
 println!("sample_bbox [{xmin},{ymin},{xmax},{ymax}] peer_margin {margin} violation_indices {:?}",violations);
 assert!(max_squared_error<=1.);assert!(controls[1].x<xmin&&controls[2].x<xmin);assert_eq!(violations,vec![1]);
 },other=>panic!("numeric replay mismatch {:?}",other)}
}
