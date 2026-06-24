#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function usage() {
  console.log('Usage: node migrate_associated_devices.js [seed.json path] [--inplace]');
  console.log('If --inplace is provided (default when omitted), the file will be updated and a backup created.');
}

const argv = process.argv.slice(2);
if (argv.includes('-h') || argv.includes('--help')) {
  usage();
  process.exit(0);
}

const seedPath = argv[0] ? path.resolve(argv[0]) : path.resolve(__dirname, '..', 'seed.json');
const inplace = argv.includes('--inplace') || !argv.includes('--out');

if (!fs.existsSync(seedPath)) {
  console.error('Seed file not found:', seedPath);
  process.exit(2);
}

const raw = fs.readFileSync(seedPath, 'utf8');
let data;
try {
  data = JSON.parse(raw);
} catch (e) {
  console.error('Failed to parse JSON:', e.message);
  process.exit(3);
}

let changed = false;
const changedUsers = [];
if (data.users && typeof data.users === 'object') {
  for (const uid of Object.keys(data.users)) {
    const user = data.users[uid];
    if (!user || typeof user !== 'object') continue;
    const ad = user.associated_devices;
    if (Array.isArray(ad)) {
      const map = {};
      for (const id of ad) {
        if (typeof id === 'string' && id.length) map[id] = true;
      }
      user.associated_devices = map;
      changed = true;
      changedUsers.push(uid);
    }
  }
}

if (!changed) {
  console.log('No array-form associated_devices found. No changes made.');
  process.exit(0);
}

const backupPath = seedPath + '.bak.' + Date.now();
fs.writeFileSync(backupPath, raw, 'utf8');
fs.writeFileSync(seedPath, JSON.stringify(data, null, 2) + '\n', 'utf8');

console.log('Migrated associated_devices for users:', changedUsers.join(', '));
console.log('Backup of original written to:', backupPath);
console.log('Updated seed file written to:', seedPath);

process.exit(0);
