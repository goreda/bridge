#[path="../src/gpos_verified.rs"] mod gpos_verified;
mod export_gpos {pub use kni_metrics::export_gpos::*;}
use kni_metrics::export_gpos::PairTarget;
use kni_metrics::gpos_pairpos1::{write_kern_pairpos1, PairKern};
#[test] fn same_bytes_as_verification_lane(){
    let mut a=vec![];let mut b=vec![];
    for l in 0..40u16 { for r in (0..40u16).step_by(3) { let k=(l as i32-r as i32)*-10;
        a.push(PairTarget{left:l,right:r,kern:k,locked:true}); b.push(PairKern{left:l,right:r,x_advance:k}); } }
    assert_eq!(gpos_verified::write(&a).unwrap(), write_kern_pairpos1(40,&b).unwrap());
}
