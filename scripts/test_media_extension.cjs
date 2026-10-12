// Compatibility entry point for the original test command.
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const result = spawnSync(process.execPath, ['--test', path.join(__dirname, 'media_extension.test.js')], {
    stdio: 'inherit',
});
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
