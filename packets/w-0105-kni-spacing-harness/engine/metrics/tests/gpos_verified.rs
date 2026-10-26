#[path="../src/gpos_verified.rs"] mod gpos_verified;
mod export_gpos {pub use kni_metrics::export_gpos::*;}
use kni_metrics::export_gpos::PairTarget;
fn target(l:u16,r:u16,k:i32)->PairTarget{PairTarget{left:l,right:r,kern:k,locked:true}}
#[test] fn ordered_exact_and_zero(){
    let a=gpos_verified::write(&[target(2,1,-20),target(1,2,0)]).unwrap();
    let b=gpos_verified::write(&[target(1,2,0),target(2,1,-20)]).unwrap();
    assert_eq!(a,b);assert_eq!(&a[..4],&[0,1,0,0]);
}
#[test] fn rejects_duplicates_unlocked_range_and_offsets(){
    assert!(gpos_verified::write(&[target(1,2,0),target(1,2,-1)]).is_err());
    assert!(gpos_verified::write(&[target(1,2,40000)]).is_err());
    let mut t=target(1,2,0);t.locked=false;assert!(gpos_verified::write(&[t]).is_err());
    let many:Vec<_>=(0..20000).map(|r|target(1,r,-20)).collect();
    assert!(gpos_verified::write(&many).is_err());
}
