import assert from 'node:assert/strict'
import test from 'node:test'

import {
  castJuryVote,
  createJuryRequestGate,
  fetchJuryReviewQueue,
  isJuryResultUncertain,
  rejectJuryCandidateAsAdmin,
  submitJuryCandidate,
  withJuryRequestTimeout
} from '../src/api/juryService.js'

const createClient = (responses) => {
  const calls = []
  return {
    calls,
    rpc(name, params = {}) {
      calls.push({ name, params })
      return Promise.resolve(responses[name])
    }
  }
}

test('陪审团队列规范化票数和权限状态', async () => {
  const client = createClient({
    get_jury_review_queue: {
      data: [{
        re_review_item_id: 'item-1',
        reason: 'missing_suit',
        item_status: 'voting',
        clothes_id: 'clothes-1',
        clothes_name: '星光长裙',
        category: '连衣裙',
        game_id: '1001',
        base_payload: { name: '星光长裙', category: '连衣裙', game_id: '1001' },
        base_suit_name: '星河梦境',
        issues: [
          { field: 'stars', kind: 'missing' },
          { field: 'suit', kind: 'conflict' }
        ],
        field_options: { stars: [4, 5] },
        candidate_id: 'candidate-1',
        candidate_payload: { suit_id: 'suit-1' },
        candidate_suit_name: '星河梦境',
        approve_count: '4',
        reject_count: 1,
        my_vote: null,
        can_submit_candidate: false,
        can_vote: true,
        is_candidate_author: false,
        can_admin_reject: true
      }],
      error: null
    }
  })

  const queue = await fetchJuryReviewQueue(client)
  assert.equal(queue.length, 1)
  assert.deepEqual(
    [queue[0].approveCount, queue[0].rejectCount, queue[0].canVote, queue[0].canAdminReject],
    [4, 1, true, true]
  )
  assert.deepEqual(queue[0].issues, [
    { field: 'stars', kind: 'missing' },
    { field: 'suit', kind: 'conflict' }
  ])
  assert.equal(queue[0].baseSuitName, '星河梦境')
  assert.equal(queue[0].candidateSuitName, '星河梦境')
  assert.deepEqual(client.calls, [{ name: 'get_jury_review_queue', params: {} }])
})

test('完整补充内容、投票和管理员终审使用固定 RPC 参数', async () => {
  const client = createClient({
    submit_jury_candidate: { data: { status: 'voting' }, error: null },
    cast_jury_vote: { data: { status: 'voting' }, error: null },
    admin_reject_jury_candidate: { data: { status: 'rejected' }, error: null }
  })

  const payload = {
    name: '星光长裙',
    game_id: '1001',
    category: '连衣裙',
    stars: 5,
    scores: { simple: 4305 },
    suit_id: 'suit-1',
    temp_suit_name: null,
    tags: null,
    needs_suit_review: false
  }
  await submitJuryCandidate(client, 'item-1', payload)
  await castJuryVote(client, 'candidate-1', 'reject')
  await rejectJuryCandidateAsAdmin(client, 'candidate-1', '资料无法核实')

  assert.deepEqual(client.calls, [
    {
      name: 'submit_jury_candidate',
      params: { p_re_review_item_id: 'item-1', p_payload: payload }
    },
    {
      name: 'cast_jury_vote',
      params: { p_candidate_id: 'candidate-1', p_vote: 'reject' }
    },
    {
      name: 'admin_reject_jury_candidate',
      params: { p_candidate_id: 'candidate-1', p_reason: '资料无法核实' }
    }
  ])
})

test('请求超过时限时返回可识别的结果未确认错误', async () => {
  await assert.rejects(
    () => withJuryRequestTimeout(
      signal => new Promise((resolve, reject) => {
        signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')))
        setTimeout(resolve, 50)
      }),
      { timeoutMs: 5 }
    ),
    error => error?.code === 'JURY_REQUEST_TIMEOUT' && error?.isTimeout === true
  )
})

test('仅最后一次队列请求可以更新页面', () => {
  const requests = createJuryRequestGate()
  const first = requests.next()
  const second = requests.next()
  assert.equal(requests.isCurrent(first), false)
  assert.equal(requests.isCurrent(second), true)
  requests.invalidate()
  assert.equal(requests.isCurrent(second), false)
})

test('超时和网络中断需要自动回读，数据库业务错误直接展示', () => {
  assert.equal(isJuryResultUncertain({ isTimeout: true }), true)
  assert.equal(isJuryResultUncertain(new Error('Failed to fetch')), true)
  assert.equal(isJuryResultUncertain({ code: '42501', message: 'permission denied' }), false)
})

test('RPC 失败时保留数据库错误', async () => {
  const rpcError = { code: '42501', message: 'permission denied' }
  const client = createClient({
    get_jury_review_queue: { data: null, error: rpcError }
  })

  await assert.rejects(
    () => fetchJuryReviewQueue(client),
    error => error === rpcError
  )
})
