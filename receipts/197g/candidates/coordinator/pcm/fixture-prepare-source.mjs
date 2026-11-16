// Test-only CLI: production dispatch with explicit local fixture gateway.
import {prepareRequestFile} from './SourcePreparationDispatch.mjs';
try{process.stdout.write(JSON.stringify(await prepareRequestFile(process.argv[2],{testGateway:process.env.M2_SOURCE_GATEWAY})));}
catch{process.stderr.write('source_preparation_refused\n');process.exitCode=1;}
