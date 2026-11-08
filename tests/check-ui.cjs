'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const files = [
  'channel-coordinator/files/wifi-channels.js',
  'channel-coordinator/files/wifi-history.js',
  'channel-coordinator/files/wifi-storage.js',
  'channel-coordinator/files/wifi-disclaimer.js',
  'channel-coordinator/files/wifi-coordinator.graphs.js',
  'channel-coordinator/files/wifi-coordinator.time.js',
  'channel-coordinator/files/wifi-coordinator.help.js',
  'channel-coordinator/files/wifi-coordinator.chart.js',
  'radio-prefer/files/wifi-clients.js'
];
for (const file of files) new Function(fs.readFileSync(path.join(root, file), 'utf8'));
console.log(`PASS: ${files.length} LuCI/graph JavaScript syntax checks`);
require('./history-cache.cjs');
require('./history-refresh.cjs');
require('./help.cjs');
require('./settings.cjs');
require('./graph-widths.cjs');
require('./time.cjs');
require('./disclaimer.cjs');
