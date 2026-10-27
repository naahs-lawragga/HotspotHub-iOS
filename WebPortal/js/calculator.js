((root) => {
  'use strict';
  function calculate(source) {
    const s = String(source).replace(/[×]/g, '*').replace(/[÷]/g, '/').replace(/[−]/g, '-');
    let i = 0;
    const ws = () => { while (i < s.length && /\s/.test(s[i])) i++; };
    function atom() {
      ws();
      if (s[i] === '(') { i++; const value = add(); ws(); if (s[i++] !== ')') throw Error('Missing closing parenthesis'); return value; }
      if (s[i] === '-') { i++; return -atom(); }
      const match = s.slice(i).match(/^(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?/i);
      if (!match) throw Error('Expected a number');
      i += match[0].length;
      return Number(match[0]);
    }
    function multiply() {
      let value = atom();
      while (true) { ws(); const op = s[i]; if (op !== '*' && op !== '/') break; i++; const rhs = atom(); value = op === '*' ? value * rhs : value / rhs; }
      return value;
    }
    function add() {
      let value = multiply();
      while (true) { ws(); const op = s[i]; if (op !== '+' && op !== '-') break; i++; const rhs = multiply(); value = op === '+' ? value + rhs : value - rhs; }
      return value;
    }
    const value = add(); ws();
    if (i !== s.length) throw Error('Unexpected input');
    if (!Number.isFinite(value)) throw Error('Result is not finite');
    return value;
  }
  root.HotspotHubCalculator = { calculate };
  if (typeof module !== 'undefined' && module.exports) module.exports = root.HotspotHubCalculator;
})(globalThis);
