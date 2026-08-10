import assert from 'node:assert/strict'
import test from 'node:test'

import { getJuryOutcome, JURY_OUTCOME } from '../src/utils/juryRules.js'

test('同意票至少五票且领先时通过', () => {
  assert.equal(getJuryOutcome(5, 0), JURY_OUTCOME.APPROVED)
  assert.equal(getJuryOutcome(6, 5), JURY_OUTCOME.APPROVED)
  assert.equal(getJuryOutcome(5, 4, 7, 8), JURY_OUTCOME.VOTING)
})

test('反对票领先至少三票时退回重审', () => {
  assert.equal(getJuryOutcome(0, 3), JURY_OUTCOME.RETURNED)
  assert.equal(getJuryOutcome(2, 5), JURY_OUTCOME.RETURNED)
  assert.equal(getJuryOutcome(1, 2, 1, 4), JURY_OUTCOME.VOTING)
  assert.equal(getJuryOutcome(1, 3, 1, 4), JURY_OUTCOME.RETURNED)
})

test('未达到任一门槛时继续投票', () => {
  assert.equal(getJuryOutcome(4, 0), JURY_OUTCOME.VOTING)
  assert.equal(getJuryOutcome(5, 5), JURY_OUTCOME.VOTING)
  assert.equal(getJuryOutcome(4, 6), JURY_OUTCOME.VOTING)
})
