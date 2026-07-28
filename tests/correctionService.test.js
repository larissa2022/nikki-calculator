import assert from 'node:assert/strict'
import test from 'node:test'

import {
  fetchCorrectionReviewQueue,
  createCorrectionRequestGate,
  fetchMyCorrectionRequests,
  isCorrectionResultUncertain,
  normalizeCorrectionReviewItem,
  reviewCorrectionRequest,
  submitCorrectionRequest,
  withCorrectionRequestTimeout
} from '../src/api/correctionService.js'
import {
  buildCorrectionAcceptedValue,
  createCorrectionReviewDraft,
  filterCorrectionClothes,
  formatCorrectionReviewValue,
  getCorrectionCurrentValue,
  getCorrectionCurrentProposalValue,
  getCorrectionScoreProposal,
  getCorrectionFieldLabel,
  getCorrectionStatusLabel,
  hasMatchingActiveCorrectionRequest,
  correctionValuesMatch,
  validateCorrectionReview
} from '../src/utils/correctionRules.js'

const createClient = responses => {
  const calls = []
  return {
    calls,
    rpc(name, params = {}) {
      calls.push({ name, params })
      return Promise.resolve(responses[name])
    }
  }
}

test('报错提交和本人记录使用固定 RPC 参数', async () => {
  const client = createClient({
    submit_correction_request: {
      data: { request_id: 'request-1', status: 'pending', idempotent: false },
      error: null
    },
    get_my_correction_requests: {
      data: [{
        request_id: 'request-1',
        clothes_id: 'clothes-1',
        clothes_name: '星光长裙',
        game_id: '1001',
        category: '连衣裙',
        field_key: 'stars',
        reason: '游戏内显示为四星，请核对图鉴。',
        proposed_patch: { stars: '4' },
        status: 'pending',
        resolution_note: null,
        created_at: '2026-07-28T00:00:00Z'
      }],
      error: null
    }
  })

  await submitCorrectionRequest(client, {
    clothesId: 'clothes-1',
    fieldKey: 'stars',
    proposedValue: '4',
    reason: '游戏内显示为四星，请核对图鉴。'
  })
  const history = await fetchMyCorrectionRequests(client)

  assert.deepEqual(client.calls, [
    {
      name: 'submit_correction_request',
      params: {
        p_clothes_id: 'clothes-1',
        p_reason: '游戏内显示为四星，请核对图鉴。',
        p_proposed_patch: { stars: '4' }
      }
    },
    { name: 'get_my_correction_requests', params: {} }
  ])
  assert.deepEqual(history[0], {
    requestId: 'request-1',
    clothesId: 'clothes-1',
    clothesName: '星光长裙',
    gameId: '1001',
    category: '连衣裙',
    fieldKey: 'stars',
    reason: '游戏内显示为四星，请核对图鉴。',
    proposedPatch: { stars: '4' },
    status: 'pending',
    resolutionNote: '',
    createdAt: '2026-07-28T00:00:00Z',
    updatedAt: null
  })
})

test('报错请求超时和网络中断被识别为结果不确定', async () => {
  await assert.rejects(
    () => withCorrectionRequestTimeout(
      signal => new Promise((resolve, reject) => {
        signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')))
        setTimeout(resolve, 50)
      }),
      { timeoutMs: 5 }
    ),
    error => error?.code === 'CORRECTION_REQUEST_TIMEOUT' && error?.isTimeout === true
  )
  assert.equal(isCorrectionResultUncertain(new Error('Failed to fetch')), true)
  assert.equal(isCorrectionResultUncertain({ code: '23514', message: 'invalid field' }), false)
})

test('仅最后一次本人记录请求可以更新页面', () => {
  const gate = createCorrectionRequestGate()
  const first = gate.next()
  const second = gate.next()
  assert.equal(gate.isCurrent(first), false)
  assert.equal(gate.isCurrent(second), true)
  gate.invalidate()
  assert.equal(gate.isCurrent(second), false)
})

test('服装搜索、当前值与自然语言状态保持一致', () => {
  const wardrobe = [
    { id: '1', name: '星光长裙', game_id: '1001', category: '连衣裙', stars: '5', suit_name: '星河梦境' },
    { id: '2', name: '晨曦短裙', game_id: '1002', category: '下装', stars: '4' }
  ]

  assert.deepEqual(filterCorrectionClothes(wardrobe, '1001').map(item => item.id), ['1'])
  assert.equal(getCorrectionCurrentValue(wardrobe[0], 'suit'), '星河梦境')
  assert.equal(getCorrectionCurrentValue(wardrobe[0], 'stars'), '5')
  assert.equal(getCorrectionFieldLabel('game_id'), '短编号')
  assert.equal(getCorrectionStatusLabel('converted_to_re_review'), '陪审中')
})

test('结果不确定时仅将内容完全一致的活动报错视为提交成功', () => {
  const payload = {
    clothesId: 'clothes-1',
    fieldKey: 'stars',
    proposedValue: '4',
    reason: '游戏内显示为四星，请核对图鉴。'
  }
  const matching = {
    ...payload,
    proposedPatch: { stars: '4' },
    status: 'pending'
  }

  assert.equal(hasMatchingActiveCorrectionRequest([matching], payload), true)
  assert.equal(hasMatchingActiveCorrectionRequest([{ ...matching, status: 'approved' }], payload), false)
  assert.equal(hasMatchingActiveCorrectionRequest([{ ...matching, reason: '另一份依据说明' }], payload), false)
  assert.equal(hasMatchingActiveCorrectionRequest([], payload), false)
})

test('结构化建议按深层内容确认幂等，转陪审状态仍视为活动请求', () => {
  const suitValue = {
    suit_id: '11111111-1111-1111-1111-111111111111',
    temp_suit_name: null,
    needs_suit_review: false
  }
  const payload = {
    clothesId: 'clothes-2',
    fieldKey: 'suit',
    proposedValue: suitValue,
    reason: '游戏内套装归属与图鉴记录不一致。'
  }
  const request = {
    clothesId: 'clothes-2',
    fieldKey: 'suit',
    proposedPatch: {
      suit: {
        needs_suit_review: false,
        temp_suit_name: null,
        suit_id: suitValue.suit_id
      }
    },
    reason: payload.reason,
    status: 'converted_to_re_review'
  }

  assert.equal(correctionValuesMatch(request.proposedPatch.suit, suitValue), true)
  assert.equal(hasMatchingActiveCorrectionRequest([request], payload), true)
  assert.deepEqual(getCorrectionCurrentProposalValue({ suit_id: null }, 'suit'), {
    suit_id: null,
    temp_suit_name: null,
    needs_suit_review: false
  })
})

test('属性选项只重建用户改动的分组，其他历史分值保持不变', () => {
  const currentScores = {
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
  const rebuiltScores = {
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
  }

  assert.equal(getCorrectionScoreProposal(currentScores, rebuiltScores, []), currentScores)
  assert.deepEqual(getCorrectionScoreProposal(currentScores, rebuiltScores, [0]), {
    ...currentScores,
    simple: 4305,
    gorgeous: 0
  })
  assert.deepEqual(getCorrectionScoreProposal(null, rebuiltScores, [0]), rebuiltScores)
})

test('管理员报错队列与处理动作使用受控 RPC', async () => {
  const client = createClient({
    get_correction_review_queue: {
      data: [{
        request_id: 'request-2',
        clothes_id: 'clothes-2',
        clothes_name: '晨曦短裙',
        game_id: '1002',
        category: '下装',
        field_key: 'stars',
        reason: '游戏内显示为四星，请核对图鉴。',
        proposed_patch: { stars: '4' },
        base_payload: { stars: 5 },
        current_value: 5,
        reporter_name: '测试用户',
        created_at: '2026-07-28T01:00:00Z',
        is_own_request: false,
        can_review: true,
        can_approve_directly: false,
        can_send_to_jury: true
      }],
      error: null
    },
    review_correction_request: {
      data: { request_id: 'request-2', status: 'converted_to_re_review', points_awarded: 0 },
      error: null
    }
  })

  const queue = await fetchCorrectionReviewQueue(client)
  await reviewCorrectionRequest(client, {
    requestId: 'request-2',
    action: 'send_to_jury',
    acceptedValue: 4,
    resolutionNote: '已经对照游戏内图鉴确认星级为四星。'
  })

  assert.deepEqual(queue[0], {
    requestId: 'request-2',
    clothesId: 'clothes-2',
    clothesName: '晨曦短裙',
    gameId: '1002',
    category: '下装',
    fieldKey: 'stars',
    reason: '游戏内显示为四星，请核对图鉴。',
    proposedPatch: { stars: '4' },
    basePayload: { stars: 5 },
    currentValue: 5,
    reporterName: '测试用户',
    createdAt: '2026-07-28T01:00:00Z',
    isOwnRequest: false,
    canReview: true,
    canApproveDirectly: false,
    canSendToJury: true
  })
  assert.deepEqual(client.calls.slice(-2), [
    { name: 'get_correction_review_queue', params: {} },
    {
      name: 'review_correction_request',
      params: {
        p_request_id: 'request-2',
        p_action: 'send_to_jury',
        p_accepted_value: 4,
        p_resolution_note: '已经对照游戏内图鉴确认星级为四星。'
      }
    }
  ])
})

test('管理员本人报错被规范化为不可处理', () => {
  const item = normalizeCorrectionReviewItem({
    request_id: 'request-self',
    is_own_request: true,
    can_review: false,
    can_approve_directly: false,
    can_send_to_jury: false
  })

  assert.equal(item.isOwnRequest, true)
  assert.equal(item.canReview, false)
  assert.equal(item.canApproveDirectly, false)
  assert.equal(item.canSendToJury, false)
})

test('管理员核对值按字段构造并阻止不完整属性分值', () => {
  const item = {
    fieldKey: 'stars',
    proposedPatch: { stars: '4' },
    basePayload: { stars: 5 }
  }
  const draft = createCorrectionReviewDraft(item)
  draft.resolutionNote = '已经对照游戏内图鉴确认星级为四星。'
  assert.equal(draft.stars, 4)
  assert.equal(buildCorrectionAcceptedValue('stars', draft), 4)
  assert.equal(validateCorrectionReview('stars', draft, 'send_to_jury'), '')

  const scoresDraft = createCorrectionReviewDraft({ fieldKey: 'scores', basePayload: { scores: {} } })
  scoresDraft.resolutionNote = '已经对照游戏内图鉴逐项核对全部属性。'
  assert.equal(validateCorrectionReview('scores', scoresDraft, 'approve_empty'), '每组属性必须一项大于 0，另一项为 0。')
  for (const [left] of [
    ['simple', 'gorgeous'], ['active', 'elegant'], ['cute', 'mature'],
    ['pure', 'sexy'], ['cool', 'warm']
  ]) scoresDraft.scores[left] = 100
  assert.equal(validateCorrectionReview('scores', scoresDraft, 'approve_empty'), '')
})

test('套装核对结果必须明确选择已有套装或无关联套装', () => {
  const draft = createCorrectionReviewDraft({ fieldKey: 'suit' })
  draft.resolutionNote = '已经对照游戏内图鉴确认没有关联套装。'
  assert.equal(validateCorrectionReview('suit', draft, 'approve_empty'), '请选择已有套装，或明确选择无关联套装。')
  draft.noSuit = true
  assert.deepEqual(buildCorrectionAcceptedValue('suit', draft), {
    suit_id: null,
    temp_suit_name: null,
    needs_suit_review: false
  })
  assert.equal(validateCorrectionReview('suit', draft, 'approve_empty'), '')
  assert.equal(formatCorrectionReviewValue({ suit_id: null }, 'suit'), '无关联套装')
})

test('空特殊标签可以构造直接补全值', () => {
  const draft = createCorrectionReviewDraft({
    fieldKey: 'tags',
    proposedPatch: { tags: '欧式古典' }
  })
  draft.resolutionNote = '已经对照游戏内图鉴确认需要补充特殊标签。'

  assert.equal(buildCorrectionAcceptedValue('tags', draft), '欧式古典')
  assert.equal(validateCorrectionReview('tags', draft, 'approve_empty'), '')
})
