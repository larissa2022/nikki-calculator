import assert from 'node:assert/strict'
import test from 'node:test'

import {
  createCorrectionRequestGate,
  fetchMyCorrectionRequests,
  isCorrectionResultUncertain,
  submitCorrectionRequest,
  withCorrectionRequestTimeout
} from '../src/api/correctionService.js'
import {
  filterCorrectionClothes,
  getCorrectionCurrentValue,
  getCorrectionFieldLabel,
  getCorrectionStatusLabel,
  hasMatchingActiveCorrectionRequest
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
  assert.equal(getCorrectionStatusLabel('converted_to_re_review'), '已转交复核')
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
