#[path = "../src/point_stream.rs"]
mod stream;
use std::collections::BTreeMap;
#[test]
fn ds2_schema_implied_midpoints_and_row_order() {
    let h = "gid\tcontour\tpoint\tx\ty\ton_curve\n";
    let rows = [
        "7\t0\t0\t0\t0\t0\n",
        "7\t0\t1\t4\t0\t0\n",
        "7\t0\t2\t4\t4\t0\n",
        "7\t0\t3\t0\t4\t0\n",
    ];
    let adv = BTreeMap::from([(7, 6.)]);
    let a = stream::decode(&(h.to_string() + &rows.concat()), &adv).unwrap();
    let b = stream::decode(
        &(h.to_string() + &rows.iter().rev().cloned().collect::<String>()),
        &adv,
    )
    .unwrap();
    assert_eq!(
        kni_geometry_prototypes::geometry_pin(&a[&7]),
        kni_geometry_prototypes::geometry_pin(&b[&7])
    );
    assert_eq!(
        a[&7].rings[0].start,
        kni_geometry_prototypes::Point { x: 0., y: 2. }
    );
}
#[test]
fn names_and_duplicate_points_rejected() {
    let a = BTreeMap::from([(7, 6.)]);
    assert!(stream::decode("gid\tname\n7\tO", &a).is_err());
    let t = "gid\tcontour\tpoint\tx\ty\ton_curve\n7\t0\t0\t0\t0\t1\n7\t0\t0\t0\t0\t1\n";
    assert!(stream::decode(t, &a).is_err());
}
#[test]
fn fractional_and_exponent_spellings_of_one_value_are_equal() {
    let a = BTreeMap::from([(7, 6.)]);
    let h = "gid\tcontour\tpoint\tx\ty\ton_curve\n";
    let one = "7\t0\t0\t0\t0\t1\n7\t0\t1\t4.5\t0\t1\n7\t0\t2\t4\t-6.103515625e-05\t1\n";
    let two = "7\t0\t0\t0\t0\t1\n7\t0\t1\t4.50\t0\t1\n7\t0\t2\t4\t-0.00006103515625\t1\n";
    let other = "7\t0\t0\t0\t0\t1\n7\t0\t1\t4.6\t0\t1\n7\t0\t2\t4\t-6.103515625e-05\t1\n";
    let pin = |s: &str| {
        let g = stream::decode(&(h.to_string() + s), &a).unwrap();
        kni_geometry_prototypes::geometry_pin(&g[&7])
    };
    assert_eq!(pin(one), pin(two));
    assert_ne!(pin(one), pin(other));
}
#[test]
fn integer_and_float_spellings_are_equal() {
    let a = BTreeMap::from([(7, 6.)]);
    let h = "gid\tcontour\tpoint\tx\ty\ton_curve\n";
    let int = "7\t0\t0\t90\t0\t1\n7\t0\t1\t4\t0\t1\n7\t0\t2\t4\t4\t1\n";
    let flt = "7\t0\t0\t90.0\t0.0\t1\n7\t0\t1\t4.0\t0\t1\n7\t0\t2\t4\t4.0\t1\n";
    let x = stream::decode(&(h.to_string() + int), &a).unwrap();
    let y = stream::decode(&(h.to_string() + flt), &a).unwrap();
    assert_eq!(
        kni_geometry_prototypes::geometry_pin(&x[&7]),
        kni_geometry_prototypes::geometry_pin(&y[&7])
    );
}
#[test]
fn nonfinite_and_malformed_coordinates_rejected() {
    let a = BTreeMap::from([(7, 6.)]);
    let h = "gid\tcontour\tpoint\tx\ty\ton_curve\n";
    for bad in ["NaN", "inf", "-inf", "infinity", "1e999", "", "1,5", "0x10", "1 "] {
        let row = format!("7\t0\t0\t{}\t0\t1\n", bad);
        assert!(stream::decode(&(h.to_string() + &row), &a).is_err(), "x {bad:?}");
        let row = format!("7\t0\t0\t0\t{}\t1\n", bad);
        assert!(stream::decode(&(h.to_string() + &row), &a).is_err(), "y {bad:?}");
    }
}
