"""Bounded typed capture plus scrubbed checker/error evidence while owning gor is alive."""
import datetime, fcntl, hashlib, importlib.util, json, os, re, subprocess, sys, time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
INTERVAL=120
MAX_BYTES=262144

def tail(path):
    try:
        with Path(path).open('rb') as f:
            f.seek(max(0,Path(path).stat().st_size-MAX_BYTES))
            return f.read(MAX_BYTES).decode('utf-8','replace')
    except OSError:return ''

WT_NUMERIC_KEYS=set('session downloadSpeed uploadSpeed downloaded receivedPayloadBytes refetchedBytes receivedTotalBytes progress numPeers fileLength ratio cpuPercent loopLagMs chunks bytesMB put evicted live piece stalling stalledPiece windowActive mpvPosAgeMs wireRequests pipelineFrozenMs verifiedCount playerSec playerMin aheadSec dlGap pumpActive evictRate id startedAtMs rangeStart rangeEnd status firstWriteMs totalMs maxWriteGapMs bytes completed pid sequence lagMs observedAtMs ok'.split())
def numeric_json(value):
    if isinstance(value,dict):return {k:numeric_json(v) for k,v in value.items() if k in WT_NUMERIC_KEYS and (v is None or isinstance(v,(bool,int,float,dict)))}
    return value

def scrub_checker_line(text):
    """Preserve diagnostic words/numbers, not private paths, URLs or credentials.
    Only called for named checker/selftest-error families, never general logs.
    """
    text=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text)
    text=re.sub(r'(?i)\b(?:https?|ftp|file)://\S+', '[url]', text)
    text=re.sub(r'(?i)\b(?:authorization\s*[:=]\s*(?:bearer\s+)?|(?:access[_-]?token|refresh[_-]?token|token|password|passwd|secret|api[_-]?key|cookie|signature|credential)\s*[:=]\s*)(?:"[^"\n]*"|\'[^\'\n]*\'|[^\s,;]+)', '[credential]', text)
    text=re.sub(r'(?<![\w])(?:[A-Za-z]:[\\/]|~/|/)[^<>\n]*?(?=(?:\s+[A-Za-z_][\w-]*=)|$)', '[path]', text)
    text=re.sub(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', '[email]', text)
    text=re.sub(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', '[ip]', text)
    text=re.sub(r'[A-Za-z0-9_+./=-]{80,}', '[opaque]', text)
    return ''.join(c if c.isprintable() else ' ' for c in text)[:1200]

def cdn_row(line):
    if 'CDN-EVIDENCE:' not in line:return None
    try:obj=json.loads(line.split('CDN-EVIDENCE:',1)[1])
    except (ValueError,TypeError):return None
    if not isinstance(obj,dict) or obj.get('event') not in ('family-body-summary','upstream-request','lane-start','lane-end','downstream-open','downstream-progress','downstream-close','downstream-pressure','priority-state','range-ok','lane-ramp','serial-fallback','ticket-renewed','capacity-search'):return None
    clean={'event':obj['event']}
    for key,values in {'ip_family':('IPv4','IPv6','unknown',4,6),'outcome':('complete','error','aborted','timeout','closed'), 'family_preference':('IPv4-first',),'proxy_mode':('direct-node-agent',),'client':('mpv','ffmpeg','curl','other'),'mode':('A6','B12','default12'),'tcp_receive_buffer_status':('unsupported-node-tcp-api',),'decision':('trial','no_gain','gain','retain')}.items():
        if obj.get(key) in values:clean[key]=obj[key]
    for key in ('connection_id','route_id','socket_request_index','socket_read_watermark','response_read_watermark','body_rate_bps','body_chunks','body_chunk_min','body_chunk_max','body_gap_max_ms','request_high_water_mark','requests','bytes','total_body_ms','mean_body_ms','rolling_samples','rolling_median_body_ms','rolling_p95_body_ms','body_bytes_per_second','socket_ms','dns_ms','connect_ms','tls_ms','headers_ms','first_byte_ms','body_ms','elapsed_ms','bytes_per_second','status','start','end','from','to','rate_bps','baseline_bps','phase','lookahead_slots','foreground_window_slots','background_window_slots','queue_ms','generation','upstream_id','request_id','mono_ms','connections','active_upstream','active_background','foreground_streams','queued_upstream','max_new_background_while_foreground','cache_bytes','cache_limit','cache_hits','coalesced','cache_misses','pending_blocks','served_bytes','local_push_waits','local_push_blocked_ms','local_readable_bytes','local_readable_high_water_mark','active','bytes_since_report','report_ms'):
        value=obj.get(key)
        if type(value) in (int,float) and 0<=value<1e18:clean[key]=value
    for key in ('ipv6_fallback','reused_socket','proxy_env_present','background','complete','diagnostic'):
        if type(obj.get(key)) is bool:clean[key]=obj[key]
    agent=obj.get('agent')
    if isinstance(agent,dict) and agent.get('family_preference')=='IPv4-first':
        clean['family_preference']='IPv4-first'
        if type(agent.get('ipv6_fallback')) is bool:clean['ipv6_fallback']=agent['ipv6_fallback']
    return 'CDN-EVIDENCE:'+json.dumps(clean,sort_keys=True,separators=(',',':'))


def write_build_provenance(project,repo,resources,snapshot):
    # verified is derived only from delivered git objects and installed bytes (gor_provenance).
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    import gor_provenance
    gor_provenance.write_provenance(project,repo,resources,snapshot)


def build_evidence(resources):
    resources=Path(resources);out=[]
    try:
        fields=dict(line.split('=',1) for line in (resources/'build-id.txt').read_text().splitlines() if '=' in line)
        if re.fullmatch('[a-f0-9]{64}',fields.get('commit','')):out.append('installed-build source_manifest_sha256='+fields['commit'])
    except (OSError,ValueError):pass
    try:
        obj=json.loads((resources/'gor-build-provenance.json').read_text())
        if obj.get('verification')=='delivered-tree-installed-bytes' and re.fullmatch('[a-f0-9]{40}',obj.get('source_commit','')) and re.fullmatch('[a-f0-9]{40}',obj.get('tree','')) and re.fullmatch('[a-f0-9]{64}',obj.get('tree_manifest_sha256','')) and re.fullmatch('[a-f0-9]{64}',obj.get('source_snapshot_sha256','')):
            out.append('installed-build source_commit='+obj['source_commit']+' tree='+obj['tree']+' tree_manifest_sha256='+obj['tree_manifest_sha256']+' source_snapshot_sha256='+obj['source_snapshot_sha256']+' verification=delivered-tree-installed-bytes')
        else:out.append('installed-build provenance=UNVERIFIED')
    except (OSError,ValueError,TypeError):out.append('installed-build provenance=UNVERIFIED')
    return out


def extract(name,text):
    out=[];checker_count=0;current_run=None
    def emit(row):
        bound=row
        if re.search(r'(?:^| )(?:checker:|3D-CHECK|selftest-stage|model-load|gor3d-selftest)',row) and '3D-CHECK run run_id=' not in row:
            bound+=' run_id='+(current_run or 'unbound')
        out.append(bound)
    for line in text.splitlines():
        stamp=re.search(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z',line)
        prefix=(stamp[0]+' ') if stamp else ''
        cdn=cdn_row(line)
        if cdn:
            emit(prefix+cdn);continue
        marker=re.search(r'3D-CHECK run run_id=([a-f0-9]{32}) supervisor_pid=(\d{1,16}) worker_pid=(\d{1,16}) build_manifest=([a-f0-9]{64}|unavailable)(?=\s|$)',line)
        if marker:
            current_run=marker[1]
            emit(prefix+marker[0]);continue
        # arch-199b launch identity: installed BuildID sha, delivered archive/gor
        # tree sha, launch time. Typed fields only; one row per app launch.
        launch_id=re.search(r'\[GOR\] build-id ([0-9a-f]{64}|unknown) tree=([0-9a-f]{40}|unknown) launch=(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)(?=\s|$)',line)
        if launch_id:
            emit(prefix+'GOR-LAUNCH v1 build='+launch_id[1]+' tree='+launch_id[2]+' launch='+launch_id[3]);continue
        if name=='wt_full.log':
            match=re.search(r'(STATS|STORE|WT_DIAG):(\{.*\})',line)
            if match:
                try:
                    obj=json.loads(match[2]);clean=numeric_json(obj)
                    if match[1]=='WT_DIAG' and obj.get('kind') in ['http-first-write','http-latency','node-sample-start','node-sample-end']:clean['kind']=obj['kind']
                    if match[1]=='WT_DIAG' and obj.get('kind')=='self':
                        clean['kind']='self'
                        if re.fullmatch(r'[0-9a-f]{64}',str(obj.get('sha256',''))):clean['sha256']=obj['sha256']
                        if re.fullmatch(r'v[0-9]+(?:\.[0-9]+)*(?:-dev)?',str(obj.get('version',''))):clean['version']=obj['version']
                    emit(prefix+match[1]+':'+json.dumps(clean,sort_keys=True,separators=(',',':')))
                except (ValueError,TypeError):pass
            continue
        #194b prepared edit lifecycle and default-off uniform research receipt.
        if '3D-RENDER v1 ' in line:
            fields=[]
            for key,pattern in {'event':r'preferences|load|started|finished','generation':r'\d{1,20}','shot':r'\d{1,10}','debounce_ms':r'\d{1,6}','fresh':r'true|false','published':r'true|false','current':r'true|false'}.items():
                match=re.search(r'\b'+key+'=('+pattern+r')(?=\s|$)',line)
                if match:fields.append(key+'='+match[1])
            if fields:emit(prefix+'3D-RENDER v1 '+' '.join(fields))
            continue
        if 'GOR-RGBD-UNIFORM v1 ' in line:
            try:
                obj=json.loads(line.split('GOR-RGBD-UNIFORM v1 ',1)[1])
                patterns={'verdict':r'PASS|FAIL','platform':r'Darwin|Linux','mpv':r'mpv v?\d+\.\d+\.\d+','base_sha256':r'[a-f0-9]{64}','changed_sha256':r'[a-f0-9]{64}','restored_sha256':r'[a-f0-9]{64}'}
                clean={k:obj[k] for k,pattern in patterns.items() if isinstance(obj.get(k),str) and re.fullmatch(pattern,obj[k])}
                if obj.get('rollout') is False:clean['rollout']=False
                if clean:emit(prefix+'GOR-RGBD-UNIFORM v1 '+json.dumps(clean,sort_keys=True))
            except (ValueError,TypeError):pass
            continue
        #194b installed-slot receipt: exact hash/variant, no private config path.
        shader=re.search(r'\b(3D-SHADER-MISMATCH|3D-SHADER) ',line)
        if shader:
            fields=[]
            patterns={'reason':r'route|tools','expected':r'native|legacy|extended|pack|none','installed':r'legacy|extended|pack|none','sha256':r'[a-fA-F0-9]{64}|none|unavailable','verdict':r'PASS|FAIL','verification':r'installed_shader'}
            for key,pattern in patterns.items():
                match=re.search(r'\b'+key+'=('+pattern+r')(?=\s|$)',line)
                if match:fields.append(key+'='+match[1])
            entry=re.search(r'\bentry=(.*?) verdict=',line)
            if entry and entry[1]!='none':
                base=re.split(r'[/\\]',entry[1])[-1]
                if base in ('vr180-look-shader-a.glsl','vr180-look-shader-b.glsl'):
                    fields+=['entry_basename='+base,'entry_sha256='+hashlib.sha256(entry[1].encode()).hexdigest()]
            if fields:emit(prefix+shader[1]+' '+' '.join(fields))
            continue
        # Preserve the actual checker diagnosis and selftest error words, bounded
        # and scrubbed. These were previously dropped despite family FAIL lines.
        diagnostic=line.removeprefix('background-result: ')
        error=re.search(r'gor3d-selftest v1 error ',diagnostic)
        if diagnostic.startswith('checker: ') or error:
            if checker_count<160:
                diagnostic=diagnostic if diagnostic.startswith('checker: ') else diagnostic[error.start():]
                emit(prefix+scrub_checker_line(diagnostic));checker_count+=1
            continue
        # Fixed numeric camera/key lifecycle receipts. Never arbitrary strings or paths.
        family=next((f for f in ('HEAD-CAPTURE','HEAD-KEY','HEAD-STATE') if f+' ' in line),None)
        if family:
            fields=[]
            patterns={'event':r'owner-acquire|owner-release|start-request|stop-request|stop-pending|delegate|state-stopping|privacy-off|privacy-enable|consumer-start|consumer-stop|quit-request|start-rejected-quit|hardware-started|hardware-stopped|state-idle|state-authorizing|state-starting|state-running|state-failed|received|matched|dispatch|apply|helper-exit|helper-kill|helper-failed',
                      'state':r'idle|authorizing|starting|running|stopping|failed',
                      'owner':r'[0-4]','attached':r'true|false','elapsed_s':r'\d{1,6}','consumers':r'\d{1,6}','generation':r'\d{1,20}','keyCode':r'\d{1,3}',
                      'status':r'\d{1,6}','reason':r'[a-z0-9\-]{1,32}',
                      'ambient':r'true|false','paused':r'true|false','running':r'true|false','enabled':r'true|false','loaded':r'true|false','active':r'true|false',
                      'repeat':r'true|false','music':r'true|false','iptv':r'true|false','panel':r'true|false'}
            for key,pattern in patterns.items():
                match=re.search(r'\b'+key+'=('+pattern+r')(?=\s|$)',line)
                if match:fields.append(key+'='+match[1])
            if fields:emit(prefix+family+' '+' '.join(fields))
            continue
        #193i correlate route/probe/store without publishing private filenames or IDs.
        if any(family+' ' in line for family in ('vrOpenRoute','vrProbeResult')):
            family='vrOpenRoute' if 'vrOpenRoute ' in line else 'vrProbeResult'
            fields=[]
            file=re.search(r'\bfile=(.*?) generation=',line)
            if file:fields.append('file_sha256='+hashlib.sha256(file[1].encode()).hexdigest())
            film=re.search(r'\bfilm=(.*?) file=',line)
            if film:fields.append('film_sha256='+hashlib.sha256(film[1].encode()).hexdigest())
            for key,pattern in [('generation',r'\d{1,16}'),('metadata',r'none|auto|flat2D|sbsFull|sbsHalf|tbFull|tbHalf|vr180SBS|vr180TB|vr360Mono|vr360TB'),('tag',r'none|flat2D|sbsFull|sbsHalf|tbFull|tbHalf|vr180SBS|vr180TB'),('detected',r'flat2D|sbsFull|sbsHalf|tbFull|tbHalf|vr180SBS|vr180TB|vr360Mono|vr360TB'),('projection',r'none|unsupported|flat-sbs|flat-tb|vr180|vr180-tb|vr360-mono|vr360-tb')]:
                match=re.search(r'\b'+key+'=('+pattern+r')(?=\s|$)',line)
                if match:fields.append(key+'='+match[1])
            if fields:emit(prefix+family+' '+' '.join(fields))
            continue
        #193k paired request/actual runtime state and close events. Filenames
        # remain private; the stable digest joins these to recognition evidence.
        if any(family+' ' in line for family in ('3D-TRANSITION','3D-VERIFIED','3D-CLOSE')):
            family=next(family for family in ('3D-TRANSITION','3D-VERIFIED','3D-CLOSE') if family+' ' in line)
            fields=[]
            file=re.search(r'\bfile=(.*?) generation=',line)
            if file:fields.append('file_sha256='+hashlib.sha256(file[1].encode()).hexdigest())
            playing=re.search(r'\bplaying_file=(.*)$',line)
            if playing:fields.append('playing_file_sha256='+hashlib.sha256(playing[1].encode()).hexdigest())
            patterns={'app_pid':r'\d{1,16}|none','generation':r'\d{1,16}|none','revision':r'\d{1,16}|none','output':r'off|full_sbs|half_sbs|over_under|vr180|anaglyph|none','previous':r'off|full_sbs|half_sbs|over_under|vr180|anaglyph|none','engine':r'nativeVR180|twoDVR180|flat_off|flat_full_sbs|flat_half_sbs|flat_over_under|flat_anaglyph|none','phase':r'requested|submitted','verdict':r'PASS|FAIL|UNVERIFIED','verification':r'route_state','layout':r'[0-6]','pack':r'[0-4]','enabled':r'true|false','expected_layout':r'[0-6]|none','expected_pack':r'[0-4]|none','expected_enabled':r'true|false|none','reason':r'stop|quit|eof|error|redirect|unknown'}
            for key,pattern in patterns.items():
                match=re.search(r'\b'+key+'=('+pattern+r')(?=\s|$)',line)
                if match:fields.append(key+'='+match[1])
            if fields:emit(prefix+family+' '+' '.join(fields))
            continue
        #193f session route lifecycle, typed values only; never IDs or filenames.
        if '3D-FILE-RESET path=' in line:
            emit(prefix+'3D-FILE-RESET reset=1');continue
        if '3D-DROPPED ' in line:
            fields=[]
            reason=re.search(r'\breason=(identityEmpty|filmMismatch)(?=\s|$)',line)
            revision=re.search(r'\brevision=(\d{1,16})(?=\s|$)',line)
            if reason:fields.append('reason='+reason[1])
            if revision:fields.append('revision='+revision[1])
            if fields:emit(prefix+'3D-DROPPED '+' '.join(fields))
            continue
        if '3D-DECISION path=store_applier ' in line:
            fields=['path=store_applier']
            film=re.search(r'\bfilm=(.*?) source=',line)
            if film:fields.append('film_sha256='+hashlib.sha256(film[1].encode()).hexdigest())
            for key,pattern in [('source',r'flat2D|sbsFull|sbsHalf|tbFull|tbHalf|vr180SBS|vr180TB|vr360Mono|vr360TB'),('engine',r'nativeVR180|twoDVR180|flat_off|flat_full_sbs|flat_half_sbs|flat_over_under|flat_anaglyph'),('output',r'off|full_sbs|half_sbs|over_under|vr180|anaglyph'),('pack','[0-4]')]:
                match=re.search(r'\b'+key+'=('+pattern+r')(?=\s|$)',line)
                if match:fields.append(key+'='+match[1])
            emit(prefix+'3D-DECISION '+' '.join(fields));continue
        # Fatal route invariant uses fixed vocabulary; never publish a raw traceback/path.
        if 'flat store kind crossed native engine' in line:
            emit(prefix+'3D-LUA-FAIL reason=flat_store_kind_crossed_native_engine')
            continue
        #193c bounded routing vocabulary, never values= payloads, filenames or errors.
        route=re.search(r'\b(3D-LUA|3D-REJECTED) ',line)
        if route:
            fields=[]
            allowed={'sender':{'store-applier','controller-outside-applier','old-store','old-sender','legacy-plannedLook','nil'},
                     'message':{'vr180-look-'+x for x in ('set-projection','set-output','set-pack','set-enabled','plan-lock')},
                     'reason':{'revision','store_kind','flat_engine'}}
            for key,choices in allowed.items():
                match=re.search(r'\b'+key+r'=([^\s]+)',line)
                if match and match[1] in choices:fields.append((key,match[1]))
            for key,pattern in (('revision',r'\d{1,16}|none|nil'),('vr_source_layout','[0-4]'),('vr_flat_mono','[01]'),('vr_pack','[0-4]')):
                match=re.search(r'\b'+key+'=('+pattern+r')(?=\s|$)',line)
                if match:fields.append((key,match[1]))
            if fields:emit(prefix+route[1]+' '+' '.join(k+'='+v for k,v in fields))
            continue
        # Typed routing evidence: keep enum values only, never the file field or arbitrary text.
        route_at = line.find('{"')
        if 'vrOpenDecision' in line and route_at >= 0:
            try:
                obj = json.loads(line[route_at:])
                allowed = {'decision': {'mono','vr180','flat-sbs','flat-tb','flat-2d3d'},
                    'reason': {'remembered','projectionMetadata','unsupportedProjectionMetadata','stereoMetadata','filename180','filenameSBS','filenameTB','filename360','monoNegative','topBottomTest','sourceMetadata','outputOff'},
                    'probeStatus': {'pending','metadataAbsent','projectionMetadata','probeFailedOrTimedOut','ffprobeUnavailable'}}
                safe = {k: obj[k] for k, values in allowed.items() if obj.get(k) in values}
                if obj.get('k') == 'vrOpenDecision' and safe: emit(prefix + 'vrOpenDecision ' + ' '.join(k+'='+v for k,v in safe.items()))
            except (ValueError, TypeError): pass
            continue
        # 3D evidence: allowlisted verdicts/devices/packages and numeric fields only.
        # Never forward raw model errors, paths, subtitles, arbitrary enum strings or process args.
        three=line.removeprefix('background-result: ')
        if three.startswith(('3D-CHECK ', '3d-load ', '3d-load-probe ', 'gor3d-selftest-cli v1 ', 'gor3d-selftest v1 ')):
            nums=re.findall(r'\b(rc|seconds|selftest_exit|errors|elapsed_ms|limit_s|in_stage_s|ms|t|code|done|total|sender_pid|target_pid|signal)=(-?\d+(?:\.\d+)?|None)(?= |$)',three)
            enums=[]
            for key,allowed in [('verdict',r'PASS|FAIL|NOT_RUN(?:\(kit_missing\))?'),('cli_complete',r'True|False'),('device',r'all|cpuAndGPU|cpuOnly'),('outcome',r'loaded|timeout|error|failed'),('killed',r'yes'),('sender',r'update_3d_check|build.sh|unattributed_by_waitpid'),('reason',r'no_log_growth|selftest_total_limit|replace_ui_bundle')]:
                m=re.search(r'\b'+key+r'=('+allowed+r')(?= |$)',three)
                if m: enums.append((key,m[1]))
            pkg=re.search(r'\b(?:encoder_fp16|bootstrap_fp16|stream_fp16|moge2_vits_\d+x\d+_fp(?:16|32))\.mlpackage\b',three)
            if pkg: enums.append(('package',pkg[0]))
            stage=re.search(r'stage=(cuts-frames|cuts-reader-close|cuts-persist|depth-setup|depth-boundary|thermal-pause|thermal-resumed|depth-frames|depth-windows|moge-keyframes|source-proxy-frames|stereo-synthesis-(?:full_sbs|vr180))(?= |$)',three)
            if stage: enums.append(('stage',stage[1]))
            family=re.match(r'3D-CHECK family ([a-zA-Z0-9_-]{1,40}) (PASS|FAIL|MISSING|NOT_RUN)$',three)
            if family: enums += [('family',family[1]),('family_verdict',family[2])]
            kind='model-load' if three.startswith(('3d-load','3d-load-probe')) else ('selftest-stage' if ' stage ' in three or ' alive ' in three else '3D-CHECK')
            if nums or enums: emit(prefix+kind+' '+' '.join(k+'='+v for k,v in enums+nums))
            continue
        # Symbols only, no binary-image list, addresses, arguments, paths or arbitrary text.
        if name.startswith('gor-wt-lag-') or name in ('gor_sample.txt','gor_mpv_sample.txt'):
            m=re.search(r'(\d+) ([A-Za-z_][A-Za-z0-9_:~<> ]{2,100})\([^\n]*?\)\s+\(in ',line)
            if m:emit('stack samples='+m[1]+' symbol='+m[2].strip())
            else:
                m=re.search(r'(\d+) (uv__[A-Za-z0-9_]+|utp_[A-Za-z0-9_]+|__close_nocancel)\s+\(in ',line)
                if m:emit('stack samples='+m[1]+' symbol='+m[2])
            continue
        # The full file is never sent. Keep only typed numeric fields from named diagnostic families.
        families=['playback-cache','playback-cost','thread-cpu','main-thread','thermal-diag','photon','photon_grain','cropdetect','window-sync','VB','SCE']
        family=next((f for f in families if ('['+f+']' in line or f+':' in line or f+' ' in line)),None)
        if 'Audio device underrun detected.' in line:family='mpv-underrun'
        if not family and name.startswith('photon-'):family='photon'
        if not family:continue
        pairs=re.findall(r'\b([A-Za-z][A-Za-z0-9_-]{0,35})=([-+]?[0-9]+(?:\.[0-9]+)?)(?=[,;\s%\]}]|$)',line)
        # No string payload, filenames, quoted subtitles, IPs, tokens or arbitrary enum values.
        pairs=[(k,v) for k,v in pairs if k.startswith('shadow_') or k in {'would','would_same','would_diff','would_paused','reuse','thermal','estimated_vf_fps','frame_drop_count','vo_delayed','mistimed','cpu_system_pct','cpu_temp_c','cpu_temp_max_c','vr','sample_age_s','utc_ms','position_s','cache_s','paused_for_cache','gor','mpv','ffmpeg','ffmpegWorkers','sampleEvery_s','win','threads','total','busy','loops','mpvPID','generation','drop','delayed','mistimed','avsync','current','zero_run','callbacks','notes','rebuilds','ticks','fanouts','listeners','proximity','alpha','windowAlpha','level','strength','mult','hint','n','pair','quilt','sample','score','vote','share'}]
        if pairs or family=='mpv-underrun':emit(prefix+family+' '+ ' '.join(k+'='+v for k,v in pairs))
    return out[-1200:]

def checker_tail(path):
    # Preserve the run marker governing a bounded tail, even after a noisy model
    # load evicts startup. Never use a later marker to label earlier verdicts.
    try:
        with Path(path).open('rb') as f:data=f.read(64*1024*1024+1)
        if len(data)>64*1024*1024:return tail(path) # unbound rather than guess
        cut=max(0,len(data)-MAX_BYTES)
        preceding=data[:cut].decode('utf-8','replace')
        markers=re.findall(r'3D-CHECK run run_id=[a-f0-9]{32} supervisor_pid=\d{1,16} worker_pid=\d{1,16} build_manifest=(?:[a-f0-9]{64}|unavailable)(?=\s|$)',preceding)
        return (markers[-1]+'\n' if markers else '')+data[cut:].decode('utf-8','replace')
    except OSError:return ''


def depth_runtime_row(line):
    # Fixed vocabulary only. A path/error suffix cannot become capture text.
    registered=re.search(r'\b3d-depth-runtime registered runner=NativePrepareRunner verified_manifest=([a-f0-9]{16}|none) depth=VDA_MoGe synthesis=(dibr_golden|mlbw_l2_inpaint_video|mlbw_l2_inpaint|row_flow_v3)(?=\s|$)',line)
    if registered:
        return '3d-depth-runtime registered=1 runner=NativePrepareRunner verified_manifest='+registered[1]+' depth=VDA_MoGe synthesis='+registered[2]
    failed=re.search(r'\b3d-kit-(read|verify) FAIL(?=\s|$)',line)
    if failed:
        reason=re.search(r'\breason=(relative_prefix_mismatch|symlink_entry|enumerator_unavailable)(?=\s|$)',line)
        return '3d-kit-'+failed[1]+' failed=1'+(' reason='+reason[1] if reason else '')
    return None

def depth_runtime_evidence(path):
    # Registration prints once at startup. The ordinary 262KB tail may have
    # evicted it before the first periodic capture. Stream a bounded full log.
    # These are observed log facts, not a current-PID or inference assertion.
    registered=None;reads=verifies=prefix_fail=seen=scanned=0;truncated=0
    try:
        with Path(path).open('rb') as log:
            for raw in log:
                scanned+=len(raw)
                if scanned>64*1024*1024:truncated=1;break
                row=depth_runtime_row(raw.decode('utf-8','replace'))
                if not row:continue
                seen=1
                if row.startswith('3d-depth-runtime'):registered=row
                if row.startswith('3d-kit-read'):reads+=1
                if row.startswith('3d-kit-verify'):verifies+=1
                if 'relative_prefix_mismatch' in row:prefix_fail+=1
    except OSError:return []
    if not seen:return ['3d-depth-runtime NOT_RUN no_observed_runtime_evidence scanned_bytes='+str(scanned)+' scan_truncated='+str(truncated)]
    rows=[registered] if registered else []
    if prefix_fail:rows.append('3d-kit-read reason=relative_prefix_mismatch count='+str(prefix_fail))
    rows.append('3d-depth-runtime log_summary registered_seen='+str(int(registered is not None))+' kit_read_fail_count='+str(reads)+' kit_verify_fail_count='+str(verifies)+' scanned_bytes='+str(scanned)+' scan_truncated='+str(truncated))
    return rows

def pose_trace_evidence(directory):
    # Numeric pose/pupil geometry only. Never images, media names or arbitrary keys.
    path=Path(directory)/'current.jsonl';rows=[]
    try:
        text=tail_pose(path)
        for line in text.splitlines():
            try:obj=json.loads(line)
            except (ValueError,TypeError):continue
            clean={}
            for key,lengths in [('raw',(0,6)),('filtered',(6,)),('euro',(0,6)),('bands',(0,6)),('pupils',(0,4)),('eyeApertures',(0,2)),('frameQuality',(0,8)),('pairedPupils',(0,4)),('eyeGeometry',(0,4)),('eyeWidths',(0,2)),('faceBox',(0,4)),('landmarkBox',(0,4)),('poseAngles',(0,3))]:
                value=obj.get(key)
                if isinstance(value,list) and len(value) in lengths and all(type(v) in (int,float) and abs(v)<1e12 for v in value):clean[key]=[round(v,7) for v in value]
            for key in ('t','confidence','distanceMode','structureReason','resetSequence','framePTS'):
                value=obj.get(key)
                if type(value) in (int,float) and abs(value)<1e12:clean[key]=round(value,7)
            for key in ('faceLost','outlier','reacquire','eyeHold'):
                if type(obj.get(key)) is bool:clean[key]=obj[key]
            for key,pattern in [('traceSession',r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}'),('traceBuild',r'(?:[0-9a-f]{40}|[0-9a-f]{64}|unknown)'),('action',r'(?:sample|recenter|trackingStop|baselineSeed)')]:
                value=obj.get(key)
                if isinstance(value,str) and re.fullmatch(pattern,value):clean[key]=value
            if 't' in clean and 'filtered' in clean:rows.append('pose-trace '+json.dumps(clean,separators=(',',':'),sort_keys=True))
    except OSError:return ['pose-trace NOT_RUN no_recorded_owner_trace']
    return rows[-900:] or ['pose-trace NOT_RUN no_valid_numeric_trace']

def convergence_evidence(path):
    # Exact numeric publication fields only, no paths/source titles/shader bodies.
    keys=set('t position sessionBirth sessionEpoch internal planLock titleStatAvailable vr_fov vr_roll vr_head_roll vr_cross_eye vr_swap_eyes vr_manual_view vr_eye_aspect vr_aspect_override vr_surface_w vr_surface_h vr_base_ipd vr_ipd_nudge vr_head_x vr_head_y vr_head_z vr_source_layout vr_flat_mono vr_flat_sbs vr_pack vr_pk_conv vr_d3_gain vr_parallax_strength vr_parallax_disparity vr_gap_frac'.split())
    rows=[]
    try:
        for line in tail_pose(path).splitlines():
            try:obj=json.loads(line)
            except (ValueError,TypeError):continue
            if not isinstance(obj,dict):continue
            clean={k:v for k,v in obj.items() if k in keys and type(v) in (int,float) and abs(v)<1e12}
            if 't' in clean and 'sessionBirth' in clean:rows.append('convergence-trace '+json.dumps(clean,sort_keys=True,separators=(',',':')))
    except OSError:return ['convergence-trace NOT_RUN no_recorded_uniforms']
    return rows[-900:] or ['convergence-trace NOT_RUN no_valid_numeric_uniforms']

def tail_pose(path):
    with Path(path).open('rb') as f:
        f.seek(max(0,Path(path).stat().st_size-4*1024*1024))
        return f.read(4*1024*1024).decode('utf-8','replace')

def identity(pid):
    try:return subprocess.check_output(['/bin/ps','-p',str(pid),'-o','lstart='],stderr=subprocess.DEVNULL,timeout=3).decode().strip()
    except (OSError,subprocess.SubprocessError):return ''

def collect(config, owner_pid, root=None):
    from session_log_paths import active
    root=Path(root) if root is not None else (active() or Path('/tmp'))
    output=['gor-periodic numeric capture','utc='+datetime.datetime.now(datetime.timezone.utc).isoformat(),'owner_pid='+str(owner_pid),'source='+config.get('source','unavailable'),'redaction=typed-numeric-symbols-and-scrubbed-checker-errors; full raw logs retained locally']
    try:
        spec=importlib.util.spec_from_file_location('gor_geometry',Path(config['project'])/'tools/gor_state_dump.py');geom=importlib.util.module_from_spec(spec);spec.loader.exec_module(geom)
        output.extend(geom.section_geometry(str(owner_pid)))
    except (OSError,ValueError,ImportError):output.append('state-geometry NOT_RUN unavailable')
    # 191j: installed-script + 3D-kit identity (content hashes only, no paths) so a running build's
    # VR180 lua/kit revision is readable from the capture alone.
    output+=build_evidence(config.get('resources',Path(__file__).resolve().parent))
    scripts=Path(config['config'])/'scripts';script_shas=[]
    try:
        for p in sorted(scripts.rglob('*.lua')):
            if p.is_file():script_shas.append(p.relative_to(scripts).as_posix()+'='+hashlib.sha256(p.read_bytes()).hexdigest())
    except OSError:pass
    output.append('installed-script-sha256='+(' '.join(script_shas) if script_shas else 'MISSING'))
    kit=Path(config.get('kit_dir') or (Path.home()/'Library/Application Support/gor/models/kit'))
    try:
        manifest_sha=[m.name+'='+hashlib.sha256(m.read_bytes()).hexdigest() for m in sorted(kit.glob('kit_manifest*.json'))]
        pkgs=sum(1 for p in kit.glob('*.mlpackage') if p.is_dir())
        output.append('kit '+((' '.join(manifest_sha)+' packages='+str(pkgs)) if manifest_sha or pkgs else 'MISSING'))
    except OSError:output.append('kit MISSING')
    names=['gor_diag.log','gor_direct.log','gor_sample.txt','gor_mpv_sample.txt','wt_full.log']
    wt=tail(root/'wt_full.log');pids=re.findall(r'STATS:\{"session":(\d+)',wt)
    if pids:names.extend(p.name for p in sorted(root.glob('gor-wt-lag-'+pids[-1]+'-*.txt'))[:4])
    sources=[(name,root/name) for name in names]
    sources.extend((name,(root if root.name.startswith('gor-log-session-') else Path(config['config']))/name) for name in ['photon-grain-size.log','photon-grain-doc.log'])
    sources.extend((name,Path(config['project'])/name) for name in ['.gor-3d-check-background.log','.gor-3d-check-last.log'])
    for name,path in sources:
        text=wt if name=='wt_full.log' else (checker_tail(path) if name.startswith('.gor-3d-check-') else tail(path))
        rows=extract(name,text)
        if name.startswith('.gor-3d-check-'):
            markers=[row for row in rows if '3D-CHECK run run_id=' in row]
            output.append('checker-source '+name+' binding='+('MARKERS_PRESENT' if markers else 'UNBOUND'))
        if name in ('gor_diag.log','gor_direct.log','.gor-3d-check-background.log','.gor-3d-check-last.log'):rows+=depth_runtime_evidence(path)
        output+=['BEGIN '+name]+(rows or ['NOT_RUN no approved numeric evidence'])+['END '+name]
    output+=['BEGIN pose-trace']+pose_trace_evidence(Path.home()/'Library/Application Support/gor/pose-traces')+['END pose-trace']
    output+=['BEGIN convergence-trace']+convergence_evidence(Path(config['config'])/'gor-convergence.jsonl')+['END convergence-trace']
    return '\n'.join(output)+'\n'

def run(config_path,pid,config_dir):
    config=json.loads(Path(config_path).read_text());config['config']=config_dir;repo=Path(config['repo'])
    # Source-approved destination only. Never inspect/print credentials or use a different remote.
    origin=subprocess.check_output(['git','-C',str(repo),'remote','get-url','origin'],stderr=subprocess.DEVNULL).decode().strip()
    if origin not in ['https://github.com/goreda/instinct.git','git@github.com:goreda/instinct.git']:return
    lock=(repo/'.git'/('gor-periodic-'+str(pid)+'.lock')).open('a')
    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:return
    owner=identity(pid)
    if not owner:return
    spec=importlib.util.spec_from_file_location('channel',Path(config_path).with_name('gor-capture-channel.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    channel=module.Channel(repo);queue=repo/'.git/gor-periodic-pending';queue.mkdir(exist_ok=True)
    while identity(pid)==owner:
        time.sleep(INTERVAL)
        if identity(pid)!=owner:break
        # Only this owner's current process, never an orphaned unrelated playback.
        children=subprocess.run(['/bin/ps','-axo','pid=,ppid=,comm='],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=5).stdout.decode('utf-8','replace')
        if not any(re.match(r'\s*\d+\s+'+str(pid)+r'\s+.*(?:/mpv|/node)$',l) for l in children.splitlines()):continue
        stamp=datetime.datetime.now().strftime('%y%m%d-%H%M%S');path=queue/(stamp+'.txt')
        if path.exists():continue
        data=collect(config,pid).encode();path.write_bytes(data[:1500000]);path.chmod(0o600)
        # Bound work to one retry per cycle. Offline captures stay local; no overlapping upload.
        pending=sorted(queue.glob('*.txt'))
        if pending:
            try:channel.send(pending[0]);pending[0].unlink()
            except (RuntimeError,OSError,subprocess.SubprocessError):pass
        # Avoid unbounded disk growth during a prolonged offline session (24h,2min cadence).
        for stale in sorted(queue.glob('*.txt'))[:-720]:stale.unlink()

if __name__=='__main__':
    try:
        if sys.argv[1]=='--write-build-provenance':write_build_provenance(*sys.argv[2:])
        else:run(sys.argv[1],int(sys.argv[2]),sys.argv[3])
    except (OSError,ValueError,subprocess.SubprocessError):sys.exit(1)
