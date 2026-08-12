import assert from 'node:assert/strict'
import test from 'node:test'

import {
  FEATURE_REQUEST_FILTER,
  normalizeFeatureRequest
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
