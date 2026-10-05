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
    deathlog(state, stats) {
      return mod.call('deathlog', JSON.stringify(state), JSON.stringify(stats || {}));
    },
    check(state) {
      return JSON.parse(mod.call('check', JSON.stringify(state)));
    },
  };
}

module.exports = { createCore };
