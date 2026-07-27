import assert from 'node:assert/strict'
import test from 'node:test'

import {
  castJuryVote,
  fetchJuryReviewQueue,
  rejectJuryCandidateAsAdmin,
  submitJuryCandidate
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
        candidate_id: 'candidate-1',
        candidate_payload: { suit_id: 'suit-1' },
        approve_count: '4',
        reject_count: 1,
        my_vote: null,
        can_submit_candidate: false,
        can_vote: true,
        is_candidate_author: false
      }],
      error: null
    }
  })

  const queue = await fetchJuryReviewQueue(client)
  assert.equal(queue.length, 1)
  assert.deepEqual(
    [queue[0].approveCount, queue[0].rejectCount, queue[0].canVote],
    [4, 1, true]
  )
  assert.deepEqual(client.calls, [{ name: 'get_jury_review_queue', params: {} }])
})

test('候选、投票和管理员终审使用固定 RPC 参数', async () => {
  const client = createClient({
    submit_jury_candidate: { data: { status: 'voting' }, error: null },
    cast_jury_vote: { data: { status: 'voting' }, error: null },
    admin_reject_jury_candidate: { data: { status: 'rejected' }, error: null }
  })

  await submitJuryCandidate(client, 'item-1', 'suit-1')
  await castJuryVote(client, 'candidate-1', 'reject')
  await rejectJuryCandidateAsAdmin(client, 'candidate-1', '资料无法核实')

  assert.deepEqual(client.calls, [
    {
      name: 'submit_jury_candidate',
      params: { p_re_review_item_id: 'item-1', p_payload: { suit_id: 'suit-1' } }
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
