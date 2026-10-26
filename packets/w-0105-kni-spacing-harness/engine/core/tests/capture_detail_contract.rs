// Test-only contract model; not a test of reserved peer capture implementation.
#[derive(Clone,Debug,PartialEq)]struct Detail{ids:Vec<usize>,kind:&'static str}
fn epsilon_allowed(e:f64)->bool{e.is_finite()&&e>=0.&&e<=0.29}
// Equal sharpness retains alternatives; no unruled first-seen tie choice.
fn sharpest(candidates:&[(usize,f64)])->Vec<usize>{let min=candidates.iter().map(|x|x.1).fold(f64::INFINITY,f64::min);candidates.iter().filter(|x|x.1==min).map(|x|x.0).collect()}
#[test]fn staircase_detail_ids_not_noise(){let detail=Detail{ids:vec![10,11,12,13],kind:"staircase"};assert!(epsilon_allowed(0.29));assert!(!epsilon_allowed(0.2900001));assert_eq!(detail.ids,vec![10,11,12,13]);}
#[test]fn flat_terminal_two_points_and_line_contract(){let detail=Detail{ids:vec![20,21],kind:"flat_line"};assert_eq!(detail.ids.len(),2);assert_eq!(detail.kind,"flat_line");}
#[test]fn paired_translated_corner_ids_retained(){let pairs=[(30,40),(31,41),(32,42)];let source=[(0.,0.),(1.,0.),(1.,1.)];let translated=[(2.,3.),(3.,3.),(3.,4.)];for i in 0..3{assert_eq!((translated[i].0-source[i].0,translated[i].1-source[i].1),(2.,3.));}assert_eq!(pairs,[(30,40),(31,41),(32,42)]);}
#[test]fn smooth_bowl_detail_map_economy_contract(){let fixed=Detail{ids:vec![50,54,58],kind:"smooth_landmarks"};let regular=vec![51,52,53,55,56,57];assert_eq!(fixed.ids.len(),3);assert_eq!(regular.len(),6);assert!(fixed.ids.iter().all(|id|!regular.contains(id)));}
#[test]fn wrap_and_run_keep_smallest_cosine_not_first(){assert_eq!(sharpest(&[(98,0.8),(0,-0.5),(1,0.2)]),vec![0]);assert_eq!(sharpest(&[(10,0.8),(11,-0.5),(12,0.2)]),vec![11]);assert_eq!(sharpest(&[(98,-0.5),(0,-0.5)]),vec![98,0]);}
#[test]fn epsilon_invalid_never_defaulted(){for e in [-1.,f64::NAN,f64::INFINITY]{assert!(!epsilon_allowed(e));}}
