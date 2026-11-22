#!/usr/bin/env python3
"""Package-boundary and build-assessment regression, independent of native playback."""
import copy, importlib.util, json, os, pathlib, subprocess, tempfile, types, unittest
from collections import Counter
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('architecture_repaired',ROOT/'tools/architecture.py')
A=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(A)

class PackageBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.graph,cls.errors=A.graph(ROOT)
        assert not cls.errors,cls.errors
        assert cls.graph.complete

    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def findings(self,path,text,graph=None):
        graph=graph or self.graph
        p=self.root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
        owners=graph.owners(path);current=owners[0]['key'] if len(owners)==1 else '-'
        rows=[[path,'swift',current,'-','fixture','1','']]
        return A.violations(self.root,rows,graph)

    def test_actual_manifests_include_tests_and_vendor(self):
        self.assertEqual(len(self.graph),124)
        self.assertEqual(self.graph.owners('Packages/gorav/Sources/subtitle-tests/SRTTests.swift')[0]['name'],'subtitle-srt-tests')
        self.assertEqual(self.graph.owners('Packages/gorav/Sources/subtitle-tests/ASSTests.swift')[0]['name'],'subtitle-ass-tests')
        self.assertFalse(self.graph.owners('Packages/gorav/Sources/subtitle-tests/Unlisted.swift'))

    def test_valid_adapter_direct_cmodule(self):
        self.assertFalse(self.findings('Packages/gorav/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift','import CFFmpeg\nimport GorAVCore\nimport GorAVNativeProbeKit\n'))

    def test_valid_declared_test_consumer(self):
        self.assertFalse(self.findings('Packages/gorav/Tests/VTPublicProducer/ProducerTests.swift','import CFFmpeg\nimport GorAVPlaybackCore\nimport GorAVFFmpegAdapter\n'))

    def test_undeclared_sibling_cmodule_and_internal_rejected(self):
        f=self.findings('Packages/gorav/Sources/GorAVCore/Boundary.swift','import CFFmpeg\nimport GorAVMetalPresenter\n')
        self.assertTrue(any(rule=='gorav-cmodule:CFFmpeg' for path,rule in f))
        self.assertTrue(any(rule=='gorav-internal:GorAVMetalPresenter' for path,rule in f))

    def test_host_cmodule_internal_and_mpv_remain_rejected(self):
        f=self.findings('Sources/gor/HostFixture.swift','import CFFmpeg\nimport GorAVPlaybackCore\nipcCommand(command)\n')
        self.assertTrue(any(rule=='gorav-cmodule:CFFmpeg' for path,rule in f))
        self.assertTrue(any(rule=='gorav-internal:GorAVPlaybackCore' for path,rule in f))
        self.assertTrue(any(rule.startswith('mpv:') for path,rule in f))

    def test_unlisted_source_cannot_borrow_target_privilege(self):
        f=self.findings('Packages/gorav/Sources/GorAVFFmpegAdapter/Unlisted.swift','import CFFmpeg\n')
        self.assertTrue(any(rule=='membership:unassigned' for path,rule in f))
        self.assertTrue(any(rule=='gorav-cmodule:CFFmpeg' for path,rule in f))

    def test_unrelated_test_directory_has_no_privileges(self):
        f=self.findings('Packages/gorav/Tests/Unknown/Probe.swift','import CFFmpeg\nimport GorAVCore\n')
        self.assertTrue(any(rule=='membership:unassigned' for path,rule in f))
        self.assertTrue(any(rule=='gorav-cmodule:CFFmpeg' for path,rule in f))

    def test_non_swift_not_adopted(self):
        self.assertFalse(self.graph.owners('Packages/gorav/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.txt'))

    def test_excludes_and_resources_not_adopted(self):
        graph=copy.deepcopy(self.graph)
        adapter=next(t for t in graph.members if t['name']=='GorAVFFmpegAdapter')
        adapter['exclude']=['FFmpegSoftwareDecoder.swift']
        self.assertFalse(graph.owners('Packages/gorav/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift'))
        adapter['exclude']=[];adapter['resources']=['FFmpegSoftwareDecoder.swift']
        self.assertFalse(graph.owners('Packages/gorav/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift'))

    def test_overlap_refuses_privilege(self):
        graph=copy.deepcopy(self.graph)
        adapter=next(t for t in graph.members if t['name']=='GorAVFFmpegAdapter')
        graph.members.append(copy.deepcopy(adapter))
        f=self.findings('Packages/gorav/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift','import CFFmpeg\n',graph)
        self.assertTrue(any(rule=='membership:overlap' for path,rule in f))
        self.assertTrue(any(rule=='gorav-cmodule:CFFmpeg' for path,rule in f))

    def test_annotated_spi_and_scoped_import_detected(self):
        f=self.findings('Sources/gor/HostFixture.swift','@_spi(NativeStereoAdmission) import GorAVEmbeddedShell\n@testable import GorAVCore\npublic import struct GorAVPlaybackCore.Frame\n')
        for name in ['GorAVEmbeddedShell','GorAVCore','GorAVPlaybackCore']:
            self.assertTrue(any(rule=='gorav-internal:'+name for path,rule in f))

    def test_unavailable_graph_no_inferred_owner(self):
        with patch.object(A.subprocess,'run',side_effect=PermissionError('fixture')):
            graph,errors=A.graph(ROOT)
        self.assertFalse(graph.complete);self.assertTrue(errors);self.assertFalse(graph)

    def test_bad_metadata_and_json_refuse(self):
        for data in ['not json',json.dumps({'targets':{}}),json.dumps({'targets':[{'name':'T','type':'regular','dependencies':None}]}),json.dumps({'targets':[{'name':'T','type':'regular','sources':['../Steal.swift']}]}),json.dumps({'targets':[],'dependencies':[{'fileSystem':[{}]}]})]:
            with self.subTest(data=data),patch.object(A.subprocess,'run',return_value=types.SimpleNamespace(returncode=0,stdout=data)):
                graph,errors=A.graph(ROOT)
            self.assertFalse(graph.complete);self.assertTrue(errors)

    def test_all_four_cmodules_require_direct_declaration(self):
        for module in ['CFFmpeg','GorAVCAtomics','GorAVAudioClock','GorAVDVRPU']:
            with self.subTest(module=module):
                f=self.findings('Sources/gor/HostFixture.swift','import '+module+'\n')
                self.assertTrue(any(rule=='gorav-cmodule:'+module for path,rule in f))

    def test_unknown_internal_module_rejected(self):
        f=self.findings('Packages/gorav/Sources/GorAVCore/Boundary.swift','import GorAVUnknown\n')
        self.assertTrue(any(rule=='gorav-internal:GorAVUnknown' for path,rule in f))

    def test_build_captures_real_architecture_status(self):
        build=(ROOT/'build.sh').read_text()
        block=build[build.index('# Architecture is an independent assessment.'):build.index('# ── swift build',build.index('# Architecture is an independent assessment.'))]
        for status,graph_status,rc,want in [('PASS','PASS',0,'PASS'),('FAIL','PASS',1,'FAIL'),('PASS','NOT_RUN',1,'NOT_RUN'),('PASS','PASS',9,'NOT_RUN')]:
            with self.subTest(status=status,graph=graph_status,rc=rc):
                script=self.root/'scripts/arch_check.py';script.parent.mkdir(exist_ok=True)
                script.write_text('import json,sys\np=sys.argv[sys.argv.index("--status-file")+1]\njson.dump('+repr({'schema':1,'assessment':status,'graph':graph_status})+',open(p,"w"))\nsys.exit('+str(rc)+')\n')
                result=subprocess.run(['bash','-c','project_root="$1"\n'+block+'\nprintf "RESULT %s %s\\n" "$architecture_status" "$architecture_qualification"','fixture',str(self.root)],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn('RESULT '+want+' '+('SELECTED_CHECKS_ONLY' if want=='PASS' else 'INCOMPLETE'),result.stdout)
        script.unlink()
        result=subprocess.check_output(['bash','-c','project_root="$1"\n'+block+'\necho RESULT "$architecture_status" "$architecture_qualification"','fixture',str(self.root)],text=True)
        self.assertIn('RESULT NOT_RUN INCOMPLETE',result)

    def test_final_capture_retains_arch_failure_after_lifecycle_pass(self):
        build=(ROOT/'build.sh').read_text()
        start=build.index('    detail="$detail"'+"$'\\n'"+'"ARCHITECTURE assessment=')
        end=build.index('    local queue=',start)
        actual_capture_assembly=build[start:end]
        state={'schema':1,'assessment':'FAIL','graph':'PASS','findings':7}
        (self.root/'.gor-architecture-status.json').write_text(json.dumps(state))
        prefix='project_root="$1"\nrc=0;ts=fixture;update_against=374c;branch=fixture;build_sha=fixture;elapsed=1;update_timer_scope=fixture\narchitecture_status=FAIL;architecture_rc=1;architecture_qualification=INCOMPLETE\ndetail="SELFTEST PASS 3/3; lifecycle PASS"\n'
        result=subprocess.check_output(['bash','-c',prefix+actual_capture_assembly+'\nprintf "%s\\n" "$msg"','fixture',str(self.root)],text=True)
        self.assertIn('rc=0 qualification=INCOMPLETE architecture=FAIL',result)
        self.assertIn('SELFTEST PASS 3/3; lifecycle PASS',result)
        self.assertIn('ARCHITECTURE assessment=FAIL rc=1',result)
        self.assertIn('ARCHITECTURE_STATUS ',result)
        self.assertIn('"findings": 7',result)

    def test_report_preserves_failure_and_writes_separate_status(self):
        ledger=self.root/'Tests/MenuStructure/required-items.json';ledger.parent.mkdir(parents=True);ledger.write_text('{"required":{},"orders":[]}')
        menu=self.root/'Menu.swift';menu.write_text('// BEGIN relocated ThreeDMenu.swift \n// END relocated ThreeDMenu.swift\n')
        for errors,complete,rc,assessment in [([],True,0,'PASS'),(['actual finding'],True,1,'FAIL'),(['graph unavailable'],False,1,'FAIL')]:
            graph=A.TargetGraph();graph.complete=complete
            status=self.root/'status.json'
            with patch.object(A,'_threed_split',return_value=types.SimpleNamespace(path=lambda root:menu)),patch.object(A,'graph',return_value=(graph,errors.copy())),patch.object(A,'provider_errors',return_value=[]),patch.object(A,'inventory',return_value=[]),patch.object(A,'bulk_errors',return_value=[]),patch.object(A,'integrity',return_value=[]),patch.object(A,'installed_overlay',return_value=True),patch('sys.argv',['architecture.py','--root',str(self.root),'--report','--status-file',str(status)]):
                result=A.main()
            self.assertEqual(result,rc)
            state=json.loads(status.read_text());self.assertEqual(state['assessment'],assessment);self.assertEqual(state['tests'],'NOT_RUN');self.assertEqual(state['compiler'],'NOT_RUN');self.assertEqual(state['lifecycle'],'NOT_RUN')

    def test_grandfathered_violations_are_not_architecture_health_pass(self):
        ledger=self.root/'Tests/MenuStructure/required-items.json';ledger.parent.mkdir(parents=True);ledger.write_text('{"required":{},"orders":[]}')
        menu=self.root/'Menu.swift';menu.write_text('// BEGIN relocated ThreeDMenu.swift \n// END relocated ThreeDMenu.swift\n')
        baseline=self.root/'architecture/arch-baseline.tsv';baseline.parent.mkdir()
        baseline.write_text('path\trule\tcount\tqueue id\tremoval condition\nSources/gor/Host.swift\tmpv:fixture\t1\tM5\tactual fix\n')
        graph=A.TargetGraph()
        status=self.root/'status.json'
        counts=Counter({('Sources/gor/Host.swift','mpv:fixture'):1})
        with patch.object(A,'_threed_split',return_value=types.SimpleNamespace(path=lambda root:menu)),patch.object(A,'graph',return_value=(graph,[])),patch.object(A,'provider_errors',return_value=[]),patch.object(A,'inventory',return_value=[]),patch.object(A,'violations',return_value=counts),patch.object(A,'integrity',return_value=[]),patch.object(A,'installed_overlay',return_value=True),patch('sys.argv',['architecture.py','--root',str(self.root),'--report','--status-file',str(status)]):
            result=A.main()
        self.assertEqual(result,1)
        state=json.loads(status.read_text())
        self.assertEqual(state['ratchet'],'PASS')
        self.assertEqual(state['assessment'],'FAIL')
        self.assertEqual(state['current_debt'],1)

if __name__=='__main__':unittest.main(verbosity=2)
