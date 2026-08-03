import test from 'node:test'
import assert from 'node:assert/strict'
import {
  CANDIDATE_EXCLUSION_STATUS,
  canRevokeCandidateExclusion,
  getCandidateExclusionStatus,
  groupCandidateExclusions
} from '../src/utils/adminGovernance.js'

const NOW = Date.parse('2026-08-03T12:00:00.000Z')

test('候选排除按当前时间区分有效、待生效、过期和已撤销', () => {
  assert.equal(getCandidateExclusionStatus({
    starts_at: '2026-08-01T00:00:00.000Z',
    ends_at: '2026-08-04T00:00:00.000Z'
  }, NOW), CANDIDATE_EXCLUSION_STATUS.ACTIVE)

  assert.equal(getCandidateExclusionStatus({
    starts_at: '2026-08-04T00:00:00.000Z',
    ends_at: '2026-08-05T00:00:00.000Z'
  }, NOW), CANDIDATE_EXCLUSION_STATUS.SCHEDULED)

  assert.equal(getCandidateExclusionStatus({
    starts_at: '2026-08-01T00:00:00.000Z',
    ends_at: '2026-08-03T12:00:00.000Z'
  }, NOW), CANDIDATE_EXCLUSION_STATUS.EXPIRED)

  assert.equal(getCandidateExclusionStatus({
    starts_at: '2026-08-01T00:00:00.000Z',
    ends_at: '2026-08-04T00:00:00.000Z',
    revoked_at: '2026-08-02T00:00:00.000Z'
  }, NOW), CANDIDATE_EXCLUSION_STATUS.REVOKED)
})

test('只有尚未结束且未撤销的候选排除可以撤销', () => {
  const current = { starts_at: '2026-08-01T00:00:00.000Z', ends_at: '2026-08-04T00:00:00.000Z' }
  const expired = { starts_at: '2026-08-01T00:00:00.000Z', ends_at: '2026-08-03T11:59:59.000Z' }
  assert.equal(canRevokeCandidateExclusion(current, NOW), true)
  assert.equal(canRevokeCandidateExclusion(expired, NOW), false)
})

test('排除列表保留已过期和已撤销历史，不再静默隐藏', () => {
  const { current, history } = groupCandidateExclusions([
    { id: 'current', starts_at: '2026-08-01T00:00:00.000Z', ends_at: '2026-08-04T00:00:00.000Z' },
    { id: 'expired', starts_at: '2026-08-01T00:00:00.000Z', ends_at: '2026-08-02T00:00:00.000Z' },
    { id: 'revoked', starts_at: '2026-08-01T00:00:00.000Z', ends_at: '2026-08-04T00:00:00.000Z', revoked_at: '2026-08-02T00:00:00.000Z' }
  ], NOW)

  assert.deepEqual(current.map(item => item.id), ['current'])
  assert.deepEqual(history.map(item => item.id), ['expired', 'revoked'])
})
