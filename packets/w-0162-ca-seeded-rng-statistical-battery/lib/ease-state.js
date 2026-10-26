'use strict';
// Asymmetric first-order easing toward a target: separate rise and fall rates (per second), frame-rate independent.
// step(value, target, dt, {rise>=0, fall>=0}) -> new value. dt in seconds. Rate 0 holds the value in that direction.
function step(value, target, dt, rates) {
  if (rates == null || !(rates.rise >= 0) || !(rates.fall >= 0)) throw new TypeError('rates.rise and rates.fall >= 0 required');
  if (!(dt >= 0)) throw new RangeError('dt must be >= 0');
  const rate = target > value ? rates.rise : rates.fall;
  return value + (target - value) * (1 - Math.exp(-rate * dt));
}
module.exports = { step };
