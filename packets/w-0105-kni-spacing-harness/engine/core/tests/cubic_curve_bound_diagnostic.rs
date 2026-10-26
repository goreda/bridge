// Bounded numeric diagnostic only. Binary64 roots, not certified interval bounds.
use kni_core::reference_slice::Point;
use kni_core::cubic_fit::{fit_run,adjacent_chord_tangents,FitPolicy,FitOutcome};
fn p(x:f64,y:f64)->Point{Point{x,y}}
fn coordinate(v:[f64;4],t:f64)->f64{let s=1.-t;v[0]*s*s*s+3.*v[1]*t*s*s+3.*v[2]*t*t*s+v[3]*t*t*t}
// Derivative /3: a*t^2+b*t+c. Exact zero branching, no production epsilon.
fn roots(v:[f64;4])->Vec<f64>{let a=-v[0]+3.*v[1]-3.*v[2]+v[3];let b=2.*(v[0]-2.*v[1]+v[2]);let c=v[1]-v[0];let mut out=Vec::new();if a==0.{if b!=0.{out.push(-c/b);}}else{let d=b*b-4.*a*c;if d>=0.{let r=d.sqrt();out.extend([(-b-r)/(2.*a),(-b+r)/(2.*a)]);}}out.retain(|t|t.is_finite()&&*t>0.&&*t<1.);out.sort_by(|a,b|a.partial_cmp(b).unwrap());out.dedup();out}
fn bound(v:[f64;4])->(f64,f64,Vec<f64>){assert!(v.iter().all(|x|x.is_finite()));let r=roots(v);let mut min=v[0].min(v[3]);let mut max=v[0].max(v[3]);for t in &r{let at=coordinate(v,*t);min=min.min(at);max=max.max(at);}assert!(min.is_finite()&&max.is_finite());(min,max,r)}
fn close(a:f64,b:f64){assert!((a-b).abs()<=1e-12,"{a} != {b}");}
#[test]fn straight_and_constant_coordinates_have_endpoint_bounds(){let(a,b,r)=bound([0.,1.,2.,3.]);assert_eq!((a,b),(0.,3.));assert!(r.is_empty());let(a,b,r)=bound([7.;4]);assert_eq!((a,b),(7.,7.));assert!(r.is_empty());}
#[test]fn quadratic_derivative_degeneracy_retains_interior_extremum(){let(a,b,r)=bound([0.,1.,1.,0.]);assert_eq!(r,vec![0.5]);close(a,0.);close(b,0.75);}
#[test]fn two_cubic_extrema_and_repeated_root(){let(a,b,r)=bound([0.,1.,-1.,0.]);assert_eq!(r.len(),2);close(a,-3f64.sqrt()/6.);close(b,3f64.sqrt()/6.);let(a,b,r)=bound([-1.,1.,-1.,1.]);assert_eq!(r,vec![0.5]);assert_eq!((a,b),(-1.,1.));}
#[test]fn outside_stationary_roots_not_used(){let(a,b,r)=bound([0.,1.,2.,4.]);assert!(r.is_empty());assert_eq!((a,b),(0.,4.));}
#[test]fn control_hull_excursion_can_exceed_curve_excursion(){let(min,max,_)=bound([0.,2.,-2.,0.]);assert!(min> -1.&&max<1.);assert!(2.>max&&-2.<min);}
#[test]fn fixed_numeric_fitted_curve_stays_in_sample_bbox(){let samples=[p(383.3903,92.2851),p(150.0182,341.4266),p(150.9631,342.6550),p(190.7565,342.7242),p(208.0580,344.0464)];let(l,r)=adjacent_chord_tangents(&samples).unwrap();let FitOutcome::Fitted{controls,max_squared_error,..}=fit_run(&samples,l,r,&FitPolicy{squared_error:1.,max_refits:6})else{panic!("numeric replay not fitted")};let x=bound(controls.map(|p|p.x));let y=bound(controls.map(|p|p.y));let xmin=samples.iter().map(|p|p.x).fold(f64::INFINITY,f64::min);let xmax=samples.iter().map(|p|p.x).fold(f64::NEG_INFINITY,f64::max);let ymin=samples.iter().map(|p|p.y).fold(f64::INFINITY,f64::min);let ymax=samples.iter().map(|p|p.y).fold(f64::NEG_INFINITY,f64::max);println!("controls {:?}\nsample_bbox [{xmin},{ymin},{xmax},{ymax}]\ncurve_x_bounds {:?}\ncurve_y_bounds {:?}\nmax_squared_error {max_squared_error}",controls,x,y);// regression pin: this packet's chord-length fit overshot the sample bbox
// (curve x-min below sample xmin); the centripetal parameterization fits it
// inside the bbox - the overshoot must not return.
assert!(x.0>=xmin,"curve x-min {} below sample xmin {}",x.0,xmin);assert!(x.1<=xmax,"curve x-max {} above sample xmax {}",x.1,xmax);assert!(max_squared_error<=1.);}
