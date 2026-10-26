// bench_trace: benchmark-facing trace runner (prototype pipeline, pre-inference-layer).
// Usage: bench_trace <in.png> <out.svg> [--eps 0.5] [--se 0.1] [--refits 6] [--scale K]
// Default scale: content-height -> 700 units (auto). se is in squared scaled units.
// In: PNG (gray or rgba). Out: SVG, one path per ring-set, nonzero fill, y-down content coords.
// Stats line to stdout: rings, spans, lines, cubics, fallbacks.
use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::Span;

fn main(){
    let mut args=std::env::args().skip(1);
    let inp=args.next().expect("usage: bench_trace <in.png> <out.svg> [--eps E] [--se S] [--refits N] [--scale K]");
    let outp=args.next().expect("out.svg missing");
    let mut eps=0.5f64; let mut se=0.1f64; let mut refits=6usize; let mut scale=-1.0f64; // -1 => auto 700/content-height
    while let Some(a)=args.next(){
        match a.as_str(){
            "--eps"=>eps=args.next().unwrap().parse().unwrap(),
            "--se"=>se=args.next().unwrap().parse().unwrap(),
            "--refits"=>refits=args.next().unwrap().parse().unwrap(),
            "--scale"=>scale=args.next().unwrap().parse().unwrap(),
            other=>{eprintln!("unknown arg {}",other);std::process::exit(2);}
        }
    }
    let png=std::fs::read(&inp).unwrap_or_else(|e|{eprintln!("read {}: {}",inp,e);std::process::exit(1);});
    let mc=capture_png(&png,eps).unwrap_or_else(|e|{eprintln!("capture: {}",e);std::process::exit(1);});
    // scale convention: content bbox height -> 700 font units (matches the 132-card prototype frame);
    // --scale overrides the factor directly. SVG is emitted back in source pixel units.
    let mut cmny=f64::INFINITY; let mut cmxy=f64::NEG_INFINITY;
    for r in &mc.rings{for p in &r.points{cmny=cmny.min(p.y);cmxy=cmxy.max(p.y);}}
    let hc=(cmxy-cmny).max(1.0);
    let s=if scale>0.0 {scale} else {700.0/hc};
    let policy=FitPolicy{squared_error:se,max_refits:refits};
    let (rings,nspans,fb,dropped)=fit_captured(&mc.rings,s,&policy);
    // content bounds of fitted output
    let mut mnx=f64::INFINITY; let mut mny=f64::INFINITY; let mut mxx=f64::NEG_INFINITY; let mut mxy=f64::NEG_INFINITY;
    let mut nline=0usize; let mut ncubic=0usize;
    for r in &rings{
        let mut pts=vec![r.start];
        for s in &r.spans{match s{
            Span::Line{end}=>{nline+=1;pts.push(*end);}
            Span::Cubic{control_one,control_two,end}=>{ncubic+=1;pts.push(*control_one);pts.push(*control_two);pts.push(*end);}
        }}
        for p in pts{mnx=mnx.min(p.x);mny=mny.min(p.y);mxx=mxx.max(p.x);mxy=mxy.max(p.y);}
    }
    let w=((mxx-mnx)/s).ceil().max(1.0); let h=((mxy-mny)/s).ceil().max(1.0);
    let fx=move |x:f64| (x-mnx)/s;         // back to source px, content-local
    let fy=move |y:f64| (mxy-y)/s;         // y-down flip against content top, source px
    let mut d=String::new();
    for r in &rings{
        d.push_str(&format!("M {:.2} {:.2} ",fx(r.start.x),fy(r.start.y)));
        for s in &r.spans{match s{
            Span::Line{end}=>d.push_str(&format!("L {:.2} {:.2} ",fx(end.x),fy(end.y))),
            Span::Cubic{control_one,control_two,end}=>d.push_str(&format!(
                "C {:.2} {:.2} {:.2} {:.2} {:.2} {:.2} ",fx(control_one.x),fy(control_one.y),fx(control_two.x),fy(control_two.y),fx(end.x),fy(end.y))),
        }}
        d.push_str("Z ");
    }
    let svg=format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{:.0}\" height=\"{:.0}\" viewBox=\"0 0 {:.2} {:.2}\"><path d=\"{}\" fill=\"#000\" fill-rule=\"nonzero\" stroke=\"none\"/></svg>\n",
        w,h,w,h,d.trim());
    std::fs::write(&outp,svg).unwrap_or_else(|e|{eprintln!("write {}: {}",outp,e);std::process::exit(1);});
    println!("bench_trace: in={} rings={} spans={} lines={} cubics={} fallbacks={} dropped_rings={} eps={} se={} refits={} scale={:.4} bbox={:.0}x{:.0}px",
        inp,rings_len(&mc),nspans,nline,ncubic,fb,dropped,eps,se,refits,s,w,h);
}
fn rings_len(mc:&kni_core::capture::MeasuredContour)->usize{mc.rings.len()}
