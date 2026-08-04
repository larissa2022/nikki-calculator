import assert from 'node:assert/strict'
import test from 'node:test'

import {
  buildJuryVoteUpdate,
  buildJuryCandidatePayload,
  buildJuryCandidateSubmissionPayload,
  createJuryCandidateForm,
  describeJuryIssues,
  formatJuryFieldValue,
  getEditableJuryFields,
  getReadonlyJuryFields
} from '../src/utils/juryReview.js'

const payload = {
  name: '星光长裙',
  game_id: '1001',
  category: '连衣裙',
  stars: 5,
  scores: {
    simple: 4305,
    gorgeous: 0,
    active: 4305,
    elegant: 0,
    cute: 4305,
    mature: 0,
    pure: 4305,
    sexy: 0,
    cool: 4305,
    warm: 0
  },
  suit_id: null,
  temp_suit_name: null,
  tags: null,
  needs_suit_review: false
}

test('完整资料可还原为审核表单并无损提交', () => {
  const form = createJuryCandidateForm(payload)
  assert.equal(form.pair1, 'simple')
  assert.equal(form.grade1, '完美')
  assert.equal(form.suit_status, 'none')
  assert.deepEqual(buildJuryCandidatePayload(form), payload)
})

test('只开放缺失或冲突字段，其他字段保持只读', () => {
  const issues = [
    { field: 'stars', kind: 'missing' },
    { field: 'pair3', kind: 'conflict' },
    { field: 'suit', kind: 'conflict' }
  ]
  const readonly = getReadonlyJuryFields(issues)
  assert.deepEqual(getEditableJuryFields(issues), ['stars', 'pair3', 'suit'])
  assert.equal(readonly.includes('stars'), false)
  assert.equal(readonly.includes('pair3'), false)
  assert.equal(readonly.includes('grade3'), false)
  assert.equal(readonly.includes('suit'), false)
  assert.equal(readonly.includes('name'), true)
  assert.equal(readonly.includes('pair1'), true)
})

test('待补套装不会被误判为纯散件，明确选择后只修改套装字段', () => {
  const unusualScores = {
    simple: 3210,
    gorgeous: 0,
    active: 2870,
    elegant: 0,
    cute: 1980,
    mature: 0,
    pure: 1760,
    sexy: 0,
    cool: 1540,
    warm: 0
  }
  const basePayload = {
    ...payload,
    scores: unusualScores,
    tags: '欧式古典'
  }
  const issues = [{ field: 'suit', kind: 'missing' }]
  const form = createJuryCandidateForm(basePayload, issues)

  assert.equal(form.suit_status, '')

  form.suit_status = 'none'
  const candidate = buildJuryCandidatePayload(form, basePayload, issues)

  assert.deepEqual(candidate.scores, unusualScores)
  assert.equal(candidate.name, basePayload.name)
  assert.equal(candidate.category, basePayload.category)
  assert.equal(candidate.stars, basePayload.stars)
  assert.equal(candidate.tags, basePayload.tags)
  assert.equal(candidate.suit_id, null)
  assert.equal(candidate.needs_suit_review, false)
})

test('历史待补套装只向数据库提交套装字段，避免被旧资料缺项阻断', () => {
  const completePayload = { ...payload, suit_id: 'suit-1' }
  assert.deepEqual(buildJuryCandidateSubmissionPayload({
    reason: 'missing_suit',
    issues: [{ field: 'suit', kind: 'missing' }]
  }, completePayload), { suit_id: 'suit-1' })
  assert.equal(buildJuryCandidateSubmissionPayload({
    reason: 'field_conflict',
    issues: [{ field: 'suit', kind: 'conflict' }]
  }, completePayload), completePayload)
})

test('问题提示分别列出缺失项和冲突项', () => {
  assert.deepEqual(describeJuryIssues([
    { field: 'stars', kind: 'missing' },
    { field: 'pair3', kind: 'conflict' }
  ]), {
    missing: ['星级'],
    conflicts: ['第三组属性']
  })
  assert.equal(formatJuryFieldValue(payload, 'pair1'), '简约（4305）')
  assert.equal(formatJuryFieldValue(payload, 'suit'), '无关联套装（纯散件）')
})

test('投票结果可立即驱动计数、退回状态和积分提示', () => {
  assert.deepEqual(buildJuryVoteUpdate({
    approve_count: 2,
    reject_count: 3,
    approve_weight: 3,
    reject_weight: 5,
    my_vote: 'reject',
    my_vote_weight: 2,
    my_voter_level: 2,
    my_review_note: '证据不足',
    status: 'returned',
    points_awarded: 1
  }), {
    approveCount: 2,
    rejectCount: 3,
    approveWeight: 3,
    rejectWeight: 5,
    myVote: 'reject',
    myVoteWeight: 2,
    myVoterLevel: 2,
    myReviewNote: '证据不足',
    status: 'returned',
    pointsAwarded: 1
  })
})
