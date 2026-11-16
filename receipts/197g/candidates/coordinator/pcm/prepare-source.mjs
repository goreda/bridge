// node prepare-source.mjs PRIVATE_REQUEST_PATH. No fixture override in this CLI.
import {prepareRequestFile} from './SourcePreparationDispatch.mjs';
try{process.stdout.write(JSON.stringify(await prepareRequestFile(process.argv[2])));}
catch{process.stderr.write('source_preparation_refused\n');process.exitCode=1;}
