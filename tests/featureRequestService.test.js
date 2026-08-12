import assert from 'node:assert/strict'
import test from 'node:test'

import {
  availableFeatureRequestAdminActions,
  FEATURE_REQUEST_FILTER,
  normalizeFeatureRequest,
  validateFeatureRequestAdminDecision
} from '../src/utils/featureRequests.js'

test('优化建议公开行不暴露作者身份并规范化点赞状态', () => {
  assert.deepEqual(normalizeFeatureRequest({
    request_id: 'request-1',
    title: '  增加筛选条件  ',
    description: '  希望可以按来源筛选衣服  ',
    status: FEATURE_REQUEST_FILTER.PLANNED,
    public_response: ' 已纳入计划 ',
    like_count: '12',
    has_liked: true,
    can_withdraw: false,
    created_at: '2026-08-12T12:00:00Z'
  }), {
    requestId: 'request-1',
    title: '增加筛选条件',
    description: '希望可以按来源筛选衣服',
    status: 'planned',
    visibility: 'public',
    publicResponse: '已纳入计划',
    likeCount: 12,
    hasLiked: true,
    canWithdraw: false,
    duplicateOf: null,
    authorId: null,
    authorName: '',
    createdAt: '2026-08-12T12:00:00Z',
    updatedAt: null,
    handledAt: null
  })
})

test('异常点赞数和布尔值按安全默认值处理', () => {
  const row = normalizeFeatureRequest({
    request_id: 'request-2',
    title: '标题',
    description: '说明',
    like_count: -3,
    has_liked: 'true',
    can_withdraw: 1
  })

  assert.equal(row.likeCount, 0)
  assert.equal(row.hasLiked, false)
  assert.equal(row.canWithdraw, false)
})

test('管理员只看到当前状态可执行的处理动作', () => {
  assert.deepEqual(
    availableFeatureRequestAdminActions({ status: 'pending', visibility: 'public' }).map(item => item.value),
    ['plan', 'not_feasible', 'mark_duplicate', 'hide']
  )
  assert.deepEqual(
    availableFeatureRequestAdminActions({ status: 'planned', visibility: 'public' }).map(item => item.value),
    ['reopen', 'hide']
  )
  assert.deepEqual(
    availableFeatureRequestAdminActions({ status: 'pending', visibility: 'withdrawn' }),
    []
  )
  assert.deepEqual(
    availableFeatureRequestAdminActions({ status: 'pending', visibility: 'hidden' }).map(item => item.value),
    ['restore']
  )
})

test('管理员处理表单按动作要求必要字段', () => {
  assert.equal(validateFeatureRequestAdminDecision({}), '请先选择处理动作。')
  assert.equal(validateFeatureRequestAdminDecision({ action: 'plan', reason: ' ' }), '请填写至少 2 个字的内部处理记录。')
  assert.equal(validateFeatureRequestAdminDecision({ action: 'plan', reason: '纳入计划' }), '')
  assert.match(validateFeatureRequestAdminDecision({ action: 'not_feasible', reason: '技术限制' }), /公开说明/)
  assert.equal(validateFeatureRequestAdminDecision({
    action: 'not_feasible', reason: '技术限制', publicResponse: '第一版暂不支持'
  }), '')
  assert.match(validateFeatureRequestAdminDecision({ action: 'mark_duplicate', reason: '内容重复' }), /原建议/)
  assert.equal(validateFeatureRequestAdminDecision({
    action: 'mark_duplicate', reason: '内容重复', duplicateOf: 'request-1'
  }), '')
})
