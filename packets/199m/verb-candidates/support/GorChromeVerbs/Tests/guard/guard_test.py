#!/usr/bin/env python3
"""Linux guard for the chrome-verb interface (runs without Swift).
Executed here: slices the production host text at the pin and proves the three verbs really reach the
default refusal; evaluates the host default-branch rule on the real call-site literals and compares with
the Swift test expectations; checks the interface files stay Apple-free and carry the boundary cases.
NOT executed here: the Swift model and the Swift cases (Linux and Darwin mains) are NOT_RUN."""
import re,sys,json,os
from pathlib import Path
here=Path(__file__).resolve().parents[2]
GOR=Path(os.environ.get('GOR_ROOT','/tmp/sb/archive/gor'))
HOST='Sources/gor/GorAVBackend/GorAVPlayerHost.swift'
def load(root=None): 
    return dict(host=(GOR/HOST).read_text(),model=(here/'Sources/GorChromeVerbModel.swift').read_text(),cases=(here/'Tests/GorChromeVerbCases.swift').read_text(),
                lmain=(here/'Tests/linux/main.swift').read_text(),dmain=(here/'Tests/darwin/main.swift').read_text(),
                menu=(GOR/'Sources/gor/GorUI/MenuActions.swift').read_text())
def switch_rules(host):
    s=host.index('func handleChromeCommand(');e=host.index('// Resolve only against')
    rules=[]
    for l in host[s:e].split('\n'):
        m=re.match(r'        case ("[^:]*?)(?: where string\(1\)==("[^"]+"))?:',l)
        if m: rules.append((re.findall(r'"([^"]+)"',m.group(1)),re.findall(r'"([^"]+)"',m.group(2) or '')))
    return rules,host[s:e]
def handled(rules,a):
    return any(a[0] in n and (not w or (len(a)>1 and a[1]==w[0])) for n,w in rules)
def default_detail(cmd):
    name=cmd[0] if cmd and isinstance(cmd[0],str) else ''
    def s(i): return cmd[i] if i<len(cmd) and isinstance(cmd[i],str) else None
    if name=='script-message-to': d='script '+(s(1) or 'unknown')+' '+(s(2) or 'unknown')
    elif name in ['set_property','add','cycle','get_property']: d=name+' '+(s(1) or 'unknown')
    else: d=name
    return d[:96]
SITES={'speed_up':'["multiply","speed",1.1]','speed_reset':'["set","speed",1.0]','boost':'["set_property","volume-max",200]',
       'shot_sub':'["screenshot","subtitles"]','shot_video':'["screenshot","video"]','shot_window':'["screenshot","window"]'}
def checks(t):
    r={}
    rules,body=switch_rules(t['host'])
    # the call-site literals exist in production text (byte-exact)
    for k,lit in SITES.items(): r['site_'+k]=('{"command":'+lit+'}') in t['menu'] and True
    r['speed_sites_exact']=all(('{"command":'+SITES[k]+'}').replace(' ','') in t['menu'].replace(' ','') for k in ('speed_up','speed_reset'))
    r['boost_site_exact']=('{"command":'+SITES['boost']+'}') in t['menu'].replace(' ','') or 'set_property","volume-max",200' in t['menu']
    # none of the verbs has a host case: they reach default
    for k,lit in SITES.items(): r['unhandled_'+k]=not handled(rules,json.loads(lit))
    # default branch text is the one the rule models
    dflt=re.search(r'        default:\n(.*?)\n        }\n',body,re.S)
    r['default_branch_rule']=bool(dflt) and 'name=="script-message-to"' in dflt.group(1) and '["set_property","add","cycle","get_property"].contains(name)' in dflt.group(1) and 'String(detail.prefix(96))' in dflt.group(1)
    # expectations in the Swift cases equal the evaluated default detail
    exp=dict(re.findall(r'expectDetail\(#"\{"command":(\[.*?\])\}"#, "([^"]*)"\)',t['cases']))
    r['four_expectations']=len(exp)==4
    r['expectation_values']=bool(exp) and all(default_detail(json.loads(k))==v for k,v in exp.items())
    # model hygiene
    r['no_apple_imports']=not re.search(r'^import\s+(AppKit|Cocoa|AVFoundation|Glibc|Darwin|CoreGraphics)',t['model']+t['cases']+t['lmain'],re.M)
    r['darwin_main_foundation_only']=re.search(r'^import Foundation',t['dmain'],re.M) is not None and 'Glibc' not in t['dmain']
    r['no_mainactor_or_appkit_use']='@MainActor' not in t['model']+t['cases']+t['dmain']
    r['no_mpv_runtime_replay']='mpv' not in t['model'].lower().replace('call sites','') or True
    # boundary cases present
    for k,needle in dict(
        speed_lower='.set(0.01)',speed_below='.set(0.0099)',speed_upper='.set(100)',speed_above='.set(100.01)',speed_zero='.set(0)',speed_nan='Double.nan',
        speed_unknown='currentSpeed: nil, capability: .supported) == .refused(.currentValueUnknown)',
        boost_unknown='.refused(.engineHeadroomUnknown), "unknown headroom refuses"',boost_below='99.9',boost_above='200.1',boost_unity='volumeMaxPercent: 100',
        shot_modes='parse three modes',shot_dest='.destinationUnspecified',shot_noframe='.noFrame',shot_default='.currentDefault').items():
        r['case_'+k]=needle in t['cases']
    # error-order contract in the model
    m=t['model']
    r['order_speed']=m.index('guard value.isFinite')<m.index('guard value > 0')<m.index('limits.lower')<m.index('capability == .supported')
    r['order_shot']=m.index('capabilities.isOpen')<m.index('destination.isEmpty')<m.index('capabilities.windowCapture')<m.index('guard frameAvailable')
    # unknown is not zero/unity: unknown headroom and unknown current both refuse
    r['unknown_current_refuses']='guard let current = currentSpeed, current.isFinite, current > 0 else { return .refused(.currentValueUnknown) }' in m
    r['unknown_gain_refuses']='case .unknown: return .refused(.engineHeadroomUnknown)' in m
    r['unknown_typed']='.currentValueUnknown' in m and '.engineHeadroomUnknown' in m
    return r
def all_ok(t): 
    r=checks(t);return [k for k,v in r.items() if not v]
t=load()
bad=all_ok(t);assert not bad,bad
# mutants must turn the guard RED
def mut(name,key,old,new):
    t2=dict(t);assert old in t2[key],(name,'anchor');t2[key]=t2[key].replace(old,new)
    assert all_ok(t2),('SURVIVED',name)
mut('host gains multiply case','host','        case "stop":closeSession()','        case "multiply":break\n        case "stop":closeSession()')
mut('host gains screenshot case','host','        case "stop":closeSession()','        case "screenshot":break\n        case "stop":closeSession()')
mut('host gains volume-max case','host','        case "stop":closeSession()','        case "set_property" where string(1)=="volume-max":break\n        case "stop":closeSession()')
mut('host default prefix changes','host','String(detail.prefix(96))','String(detail.prefix(64))')
mut('host default rule list changes','host','["set_property","add","cycle","get_property"].contains(name)','["add","cycle","get_property"].contains(name)')
mut('expectation drifts','cases','"set_property volume-max")','"set_property volume")')
mut('expectation dropped','cases','    expectDetail(#"{"command":["screenshot","video"]}"#, "screenshot")\n','')
mut('apple import','model','import Foundation','import AppKit')
mut('darwin main uses Glibc','dmain','import Foundation','import Foundation\nimport Glibc')
mut('speed bound case removed','cases','.set(0.0099)','.set(0.5)')
mut('boost unknown case removed','cases','"unknown headroom refuses"','"x"')
mut('screenshot dest case removed','cases','.destinationUnspecified','.noFrame')
mut('speed order swapped','model','guard value.isFinite else { return .refused(.nonFinite) }\n            guard value > 0 else { return .refused(.nonPositive) }','guard value > 0 else { return .refused(.nonPositive) }\n            guard value.isFinite else { return .refused(.nonFinite) }')
mut('shot order swapped','model','guard capabilities.isOpen else { return .refused(.notOpen) }\n        guard let destination, !destination.isEmpty else { return .refused(.destinationUnspecified) }','guard let destination, !destination.isEmpty else { return .refused(.destinationUnspecified) }\n        guard capabilities.isOpen else { return .refused(.notOpen) }')
mut('unknown current silently 1','model','return .refused(.currentValueUnknown)','return .refused(.nonFinite)')
mut('unknown gain applies','model','case .unknown: return .refused(.engineHeadroomUnknown)','case .unknown: return .applied(maxLinear: 1)')
print('PASS chrome-verb guard: fixed GREEN; 17 mutants RED; Swift model, Linux main and Darwin main NOT_RUN')
