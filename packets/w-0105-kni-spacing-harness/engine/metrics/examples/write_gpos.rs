use kni_metrics::export_gpos::{compile_kerns, ByteModel, PairTarget};
use kni_metrics::gpos::{write_gpos, PairException};
use std::io::Write;

fn main() {
    let targets = vec![
        PairTarget { left: 10, right: 20, kern: -80, locked: false },
        PairTarget { left: 10, right: 21, kern: -80, locked: false },
        PairTarget { left: 11, right: 20, kern: -40, locked: false },
        PairTarget { left: 11, right: 21, kern: -40, locked: false },
    ];
    let plan = compile_kerns(&targets, 0, ByteModel::default());
    let ex = vec![PairException { left: 30, right: 40, x_advance: -120 }];
    let bytes = write_gpos(&ex, &plan);
    std::io::stdout().write_all(&bytes).unwrap();
}
