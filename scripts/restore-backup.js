#!/usr/bin/env node
'use strict';
// Sicherung zurückspielen:
//   npm run restore            Liste der Sicherungen (neueste zuerst)
//   npm run restore -- 3       Sicherung Nr. 3 zurückspielen
// Pfade aus config.lua (backups.save_path, backups.dir) oder per --save / --dir.
// Vorher DeSmuME schließen! Die aktuelle Speicherdatei wird vorher als *.vor-wiederherstellung-<Zeit> gesichert.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

/** Liest save_path und dir aus config.lua (einfaches Auslesen der Zeichenketten). */
function readConfig(text) {
  const grab = (key) => {
    const m = new RegExp(`${key}\\s*=\\s*"([^"]*)"`).exec(text);
    return m ? m[1] : null;
  };
  const backups = /backups\s*=\s*\{([\s\S]*?)\n\s*\}/.exec(text);
  const block = backups ? backups[1] : '';
  const inBlock = (key) => {
    const m = new RegExp(`${key}\\s*=\\s*"([^"]*)"`).exec(block);
    return m ? m[1] : null;
  };
  return { savePath: inBlock('save_path') || grab('save_path'), dir: inBlock('dir') };
}

function listBackups(dir) {
  const index = path.join(dir, 'index.json');
  let names = [];
  if (fs.existsSync(index)) {
    try { names = JSON.parse(fs.readFileSync(index, 'utf8')); } catch { names = []; }
  }
  if (!names.length && fs.existsSync(dir)) names = fs.readdirSync(dir).filter((f) => f.endsWith('.dsv')).sort();
  return names.filter((n) => fs.existsSync(path.join(dir, n))).reverse();
}

function stamp(date = new Date()) {
  return date.toISOString().replace(/[:T]/g, '-').slice(0, 19);
}

/** Spielt Sicherung nr (1 = neueste) zurück. Rückgabe: { restored, kept } */
function restore({ savePath, dir, nr, now = new Date() }) {
  const list = listBackups(dir);
  const name = list[nr - 1];
  if (!name) throw new Error(`Sicherung Nr. ${nr} gibt es nicht (${list.length} vorhanden).`);
  let kept = null;
  if (fs.existsSync(savePath)) {
    kept = `${savePath}.vor-wiederherstellung-${stamp(now)}`;
    fs.copyFileSync(savePath, kept);
  }
  fs.copyFileSync(path.join(dir, name), savePath);
  return { restored: name, kept };
}

function main(argv) {
  const args = { nr: null, save: null, dir: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--save') args.save = argv[++i];
    else if (argv[i] === '--dir') args.dir = argv[++i];
    else if (/^\d+$/.test(argv[i])) args.nr = Number(argv[i]);
  }
  const cfgFile = path.join(ROOT, 'config.lua');
  const cfg = fs.existsSync(cfgFile) ? readConfig(fs.readFileSync(cfgFile, 'utf8')) : {};
  const savePath = args.save || cfg.savePath;
  const dir = path.resolve(ROOT, args.dir || cfg.dir || 'backups');
  if (!savePath) {
    console.log('Kein Pfad zur Speicherdatei: backups.save_path in config.lua setzen oder --save <Pfad> angeben.');
    return 1;
  }
  const list = listBackups(dir);
  if (!args.nr) {
    console.log(`Speicherdatei: ${savePath}\nSicherungen in ${dir} (neueste zuerst):`);
    list.forEach((n, i) => console.log(`  ${String(i + 1).padStart(2)}  ${n}`));
    if (!list.length) console.log('  (keine)');
    console.log('\nZurückspielen: npm run restore -- <Nr>   (vorher DeSmuME schließen)');
    return 0;
  }
  const r = restore({ savePath, dir, nr: args.nr });
  console.log(`Zurückgespielt: ${r.restored}`);
  if (r.kept) console.log(`Bisherige Speicherdatei gesichert als: ${r.kept}`);
  console.log('Jetzt DeSmuME starten und den Spielstand laden. Der Server meldet den älteren Stand allen Spielern.');
  return 0;
}

if (require.main === module) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (e) {
    console.error(`Fehler: ${e.message}`);
    process.exit(1);
  }
}

module.exports = { readConfig, listBackups, restore };
