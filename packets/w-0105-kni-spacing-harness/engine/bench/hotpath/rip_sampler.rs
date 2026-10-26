//! rip_sampler.rs - SPEED-2 ptrace sampling profiler (new bench file, additive).
//!
//! std-only, x86_64 Linux. Build with plain rustc (no Cargo involvement):
//!   rustc -O -o rip_sampler rip_sampler.rs
//!
//! usage: rip_sampler <pid> <hz> <out.tsv>
//! Attaches (PTRACE_SEIZE) to every thread of <pid>, samples the instruction
//! pointer at <hz> via PTRACE_INTERRUPT + PTRACE_GETREGS, writes
//!   ts_s <tab> tid <tab> rip_offset
//! where rip_offset = rip - image_base (PIE slide from /proc/<pid>/maps).
//! Exits when the traced process exits (PTRACE_O_EXITKILL keeps the child safe
//! if the sampler dies first).

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::time::Instant;

// x86_64 user_regs_struct field order (sys/user.h).
#[repr(C)]
#[derive(Default)]
struct Regs {
    r15: u64, r14: u64, r13: u64, r12: u64, rbp: u64, rbx: u64,
    r11: u64, r10: u64, r9: u64, r8: u64, rax: u64, rcx: u64,
    rdx: u64, rsi: u64, rdi: u64, orig_rax: u64, rip: u64,
    cs: u64, eflags: u64, rsp: u64, ss: u64,
    fs_base: u64, gs_base: u64, ds: u64, es: u64, fs: u64, gs: u64,
}

const PTRACE_SEIZE: u32 = 0x4206;
const PTRACE_INTERRUPT: u32 = 0x4207;
const PTRACE_CONT: u32 = 7;
const PTRACE_GETREGS: u32 = 12;
const PTRACE_SETOPTIONS: u32 = 0x4200;
const PTRACE_O_EXITKILL: u64 = 0x100000;

extern "C" {
    fn ptrace(request: u32, pid: i32, addr: *mut u8, data: *mut u8) -> i64;
}

fn thread_state(tid: i32) -> char {
    // /proc/<tid>/stat field 3 (single char after the comm in parens)
    if let Ok(s) = fs::read_to_string(format!("/proc/{tid}/stat")) {
        if let Some(pos) = s.rfind(')') {
            return s[pos + 2..].chars().next().unwrap_or('?');
        }
    }
    '?'
}

fn tids_of(pid: i32) -> Vec<i32> {
    let mut v = Vec::new();
    if let Ok(rd) = fs::read_dir(format!("/proc/{pid}/task")) {
        for e in rd.flatten() {
            if let Ok(tid) = e.file_name().to_string_lossy().parse::<i32>() {
                v.push(tid);
            }
        }
    }
    v.sort_unstable();
    v
}

fn image_base(pid: i32, exe: &str) -> Option<u64> {
    let maps = fs::read_to_string(format!("/proc/{pid}/maps")).ok()?;
    for line in maps.lines() {
        if line.contains(exe) {
            let start = line.split('-').next()?.trim();
            return u64::from_str_radix(start, 16).ok();
        }
    }
    None
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 4 {
        eprintln!("usage: rip_sampler <pid> <hz> <out.tsv>");
        std::process::exit(2);
    }
    let pid: i32 = a[1].parse().unwrap();
    let hz: u64 = a[2].parse().unwrap();
    let out = &a[3];
    let exe = fs::read_link(format!("/proc/{pid}/exe"))
        .map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
    let base = image_base(pid, &exe).unwrap_or(0);
    // keep the full map for offline per-mapping resolution
    if let Ok(maps) = fs::read_to_string(format!("/proc/{pid}/maps")) {
        let _ = fs::write(format!("{out}.maps"), maps);
    }

    let mut attached: BTreeMap<i32, bool> = BTreeMap::new();
    for tid in tids_of(pid) {
        unsafe {
            if ptrace(PTRACE_SEIZE, tid, std::ptr::null_mut(), std::ptr::null_mut()) == 0 {
                ptrace(PTRACE_SETOPTIONS, tid, std::ptr::null_mut(), PTRACE_O_EXITKILL as *mut u8);
                attached.insert(tid, true);
            }
        }
    }
    if attached.is_empty() {
        eprintln!("rip_sampler: could not seize any thread of {pid}");
        std::process::exit(1);
    }

    let t0 = Instant::now();
    let tick = std::time::Duration::from_nanos(1_000_000_000 / hz);
    let mut f = std::io::BufWriter::new(fs::File::create(out).unwrap());
    writeln!(f, "# exe\t{exe}\n# image_base\t{base:#x}\n# hz\t{hz}").unwrap();
    let mut next = Instant::now();
    let mut samples: u64 = 0;
    loop {
        let tids = tids_of(pid);
        if tids.is_empty() {
            break; // process gone
        }
        for &tid in &tids {
            if !attached.contains_key(&tid) {
                unsafe {
                    if ptrace(PTRACE_SEIZE, tid, std::ptr::null_mut(), std::ptr::null_mut()) == 0 {
                        ptrace(PTRACE_SETOPTIONS, tid, std::ptr::null_mut(), PTRACE_O_EXITKILL as *mut u8);
                        attached.insert(tid, true);
                    }
                }
            }
            if !attached.get(&tid).copied().unwrap_or(false) { continue; }
            let st = thread_state(tid); // read BEFORE the interrupt: a ptrace-stopped thread reads 't'
            unsafe {
                if ptrace(PTRACE_INTERRUPT, tid, std::ptr::null_mut(), std::ptr::null_mut()) != 0 {
                    continue;
                }
                let mut status: i32 = 0;
                libc_waitpid(tid, &mut status);
                if (status & 0xff) == 0x7f {
                    let mut regs = Regs::default();
                    if ptrace(PTRACE_GETREGS, tid, std::ptr::null_mut(),
                              &mut regs as *mut Regs as *mut u8) == 0 {
                        let ts = t0.elapsed().as_secs_f64();
                        writeln!(f, "{:.6}\t{}\t{}\t{:#x}", ts, tid, st, regs.rip).unwrap();
                        samples += 1;
                    }
                    ptrace(PTRACE_CONT, tid, std::ptr::null_mut(), std::ptr::null_mut());
                } else if status != 0 {
                    // thread exited or vanished
                    attached.insert(tid, false);
                }
            }
        }
        next += tick;
        let now = Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        }
        // process still alive?
        if fs::metadata(format!("/proc/{pid}")).is_err() {
            break;
        }
    }
    eprintln!("rip_sampler: {samples} samples in {:.1}s", t0.elapsed().as_secs_f64());
}

fn libc_waitpid(pid: i32, status: *mut i32) -> i32 {
    extern "C" { fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32; }
    unsafe { waitpid(pid, status, 0) }
}
