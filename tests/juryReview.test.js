import assert from 'node:assert/strict'
import test from 'node:test'

import {
  buildJuryVoteUpdate,
  buildJuryCandidatePayload,
  createJuryCandidateForm,
  describeJuryIssues,
  formatJuryFieldValue,
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
  const readonly = getReadonlyJuryFields([
    { field: 'stars', kind: 'missing' },
    { field: 'pair3', kind: 'conflict' },
    { field: 'suit', kind: 'conflict' }
  ])
  assert.equal(readonly.includes('stars'), false)
  assert.equal(readonly.includes('pair3'), false)
  assert.equal(readonly.includes('grade3'), false)
  assert.equal(readonly.includes('suit'), false)
  assert.equal(readonly.includes('name'), true)
  assert.equal(readonly.includes('pair1'), true)
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
    my_vote: 'reject',
    status: 'returned',
    points_awarded: 1
  }), {
    approveCount: 2,
    rejectCount: 3,
    myVote: 'reject',
    status: 'returned',
    pointsAwarded: 1
  })
})
