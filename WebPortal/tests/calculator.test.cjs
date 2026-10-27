const test = require('node:test');
const assert = require('node:assert/strict');
const { calculate } = require('../js/calculator.js');

test('respects multiplication precedence', () => assert.equal(calculate('2 + 3 × 4'), 14));
test('handles parentheses and unary minus', () => assert.equal(calculate('-(2 + 3) * 4'), -20));
test('supports division and decimals', () => assert.equal(calculate('7.5 ÷ 2.5'), 3));
test('rejects incomplete or trailing input', () => {
  assert.throws(() => calculate('2 +'));
  assert.throws(() => calculate('2 + 3; alert(1)'));
});
test('rejects division by zero', () => assert.throws(() => calculate('4 / 0')));
