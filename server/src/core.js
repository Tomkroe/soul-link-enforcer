'use strict';
// Dünne Hülle um die Lua-Regel-Engine (lua/core/api.lua). Keine Regel-Logik in JavaScript.
const { loadModule } = require('./lua-vm');

function createCore() {
  const mod = loadModule('core.api');
  return {
    newState(code) {
      return JSON.parse(mod.call('new_state', code));
    },
    apply(state, event) {
      const out = JSON.parse(mod.call('apply', JSON.stringify(state), JSON.stringify(event)));
      return { state: out.state, effects: Array.isArray(out.effects) ? out.effects : [] };
    },
    derive(state) {
      return JSON.parse(mod.call('derive', JSON.stringify(state)));
    },
    ledgerApply(ledger, effects, names) {
      return JSON.parse(mod.call('ledger_apply', JSON.stringify(ledger || {}), JSON.stringify(effects), JSON.stringify(names || {})));
    },
    ledgerView(ledger, pids) {
      return JSON.parse(mod.call('ledger_view', JSON.stringify(ledger), JSON.stringify(pids)));
    },
    deathlog(state, stats) {
      return mod.call('deathlog', JSON.stringify(state), JSON.stringify(stats || {}));
    },
    deathlogAll(view) {
      return mod.call('deathlog_all', JSON.stringify(view));
    },
    violations(view) {
      return mod.call('violations', JSON.stringify(view));
    },
    check(state) {
      return JSON.parse(mod.call('check', JSON.stringify(state)));
    },
  };
}

module.exports = { createCore };
