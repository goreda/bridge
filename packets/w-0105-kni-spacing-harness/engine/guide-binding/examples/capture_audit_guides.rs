//! Consume a prepared sidecar stream. Does not touch capture or font outputs.
use kni_guide_binding::*;
use std::io::{self,BufRead};
fn main()->Result<(),Box<dyn std::error::Error>>{
 let mut lines=io::stdin().lock().lines();let first=lines.next().ok_or("missing scope")??;
 let f:Vec<_>=first.split('\t').collect();if f.len()!=7||f[0]!="S"{return Err("invalid scope row".into())}
 let scope=Scope{font:f[1].into(),master:f[2].into(),style:f[3].into(),frame:f[4].into()};let source_pin=f[5].to_string();let k:f64=f[6].parse()?;
 let mut classes=Vec::new();let mut edges=Vec::new();let mut nodes=Vec::new();
 for line in lines {let line=line?;let f:Vec<_>=line.split('\t').collect();match f.first().copied(){
 Some("C") if f.len()==2=>classes.push(f[1].to_string()),
 Some("E") if f.len()==6=>edges.push(EdgeObservation{edge_id:f[1].into(),glyph:f[2].into(),class:f[3].into(),source_pin:source_pin.clone(),membership_evidence:f[4].into(),source_y:f[5].split(',').map(str::parse).collect::<Result<_,_>>()?}),
 Some("N") if f.len()==5=>nodes.push(NodeObservation{node_id:f[1].into(),scope:scope.clone(),glyph:f[2].into(),y:f[3].parse()?,source_edge_id:if f[4].is_empty(){None}else{Some(f[4].into())}}),
 _=>return Err("invalid sidecar row".into()),}}
 let inventory=derive(scope,source_pin,&classes,&edges,SpreadLimit::Image{font_units_per_source_pixel:k}).map_err(|e|format!("{:?}",e))?;
 println!("node\tclass\tnode_y\tguide_y\tsigned_offset\treason\tmode");
 for r in annotate(&inventory,&nodes,BindingMode::Measure){println!("{}\t{}\t{}\t{}\t{}\t{}\t{}",r.node_id,r.class.unwrap_or_default(),r.node_y,r.guide_y.map(|v|v.to_string()).unwrap_or_default(),r.signed_offset.map(|v|v.to_string()).unwrap_or_default(),r.reason.unwrap_or(""),r.mode);}
 Ok(())
}
