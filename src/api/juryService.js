export const JURY_REQUEST_TIMEOUT_MS = 15000

export const createJuryRequestGate = () => {
  let currentRequestId = 0
  return {
    next: () => ++currentRequestId,
    invalidate: () => { currentRequestId += 1 },
    isCurrent: requestId => requestId === currentRequestId
  }
}

export const isJuryResultUncertain = error => {
  if (error?.isTimeout) return true
  const message = String(error?.message || error || '')
  return /failed to fetch|network|load failed|connection|socket|econn/i.test(message)
}

const createTimeoutError = () => {
  const error = new Error('请求等待时间过长，结果可能已经生效，正在重新读取。')
  error.code = 'JURY_REQUEST_TIMEOUT'
  error.isTimeout = true
  return error
}

export const withJuryRequestTimeout = async (
  requestFactory,
  { timeoutMs = JURY_REQUEST_TIMEOUT_MS, signal } = {}
) => {
  const controller = new AbortController()
  const abortFromParent = () => controller.abort(signal?.reason)
  if (signal?.aborted) abortFromParent()
  else signal?.addEventListener?.('abort', abortFromParent, { once: true })

  let timeoutId
  try {
    const request = requestFactory(controller.signal)
    const timeout = new Promise((_, reject) => {
      timeoutId = setTimeout(() => {
        reject(createTimeoutError())
        controller.abort()
      }, timeoutMs)
    })
    return await Promise.race([request, timeout])
  } finally {
    clearTimeout(timeoutId)
    signal?.removeEventListener?.('abort', abortFromParent)
  }
}

const normalizeIssue = (issue) => ({
  field: String(issue?.field || ''),
  kind: issue?.kind === 'missing' ? 'missing' : 'conflict'
})

export const normalizeQueueItem = (row) => ({
  reReviewItemId: String(row?.re_review_item_id || ''),
  reason: String(row?.reason || ''),
  itemStatus: String(row?.item_status || 'pending'),
  clothesId: String(row?.clothes_id || ''),
  clothesName: String(row?.clothes_name || '未命名服装'),
  category: String(row?.category || ''),
  gameId: String(row?.game_id || ''),
  basePayload: row?.base_payload && typeof row.base_payload === 'object'
    ? row.base_payload
    : {},
  baseSuitName: String(row?.base_suit_name || ''),
  issues: (Array.isArray(row?.issues) ? row.issues : [])
    .map(normalizeIssue)
    .filter(issue => issue.field),
  fieldOptions: row?.field_options && typeof row.field_options === 'object'
    ? row.field_options
    : {},
  candidateId: row?.candidate_id ? String(row.candidate_id) : '',
  candidatePayload: row?.candidate_payload && typeof row.candidate_payload === 'object'
    ? row.candidate_payload
    : null,
  candidateStatus: row?.candidate_status ? String(row.candidate_status) : '',
  candidateSuitName: String(row?.candidate_suit_name || ''),
  candidateCreatedAt: row?.candidate_created_at || null,
  approveCount: Number(row?.approve_count) || 0,
  rejectCount: Number(row?.reject_count) || 0,
  myVote: row?.my_vote ? String(row.my_vote) : '',
  canSubmitCandidate: Boolean(row?.can_submit_candidate),
  canVote: Boolean(row?.can_vote),
  isCandidateAuthor: Boolean(row?.is_candidate_author),
  canAdminReject: Boolean(row?.can_admin_reject)
})

const callRpc = async (client, name, params = {}, options = {}) => {
  if (!client) throw new Error('缺少陪审团查询客户端')

  return withJuryRequestTimeout(async signal => {
    let request = client.rpc(name, params)
    if (typeof request?.abortSignal === 'function') {
      request = request.abortSignal(signal)
    }
    const { data, error } = await request
    if (error) throw error
    return data
  }, options)
}

export const fetchJuryReviewQueue = async (client, options = {}) => {
  const data = await callRpc(client, 'get_jury_review_queue', {}, options)
  return (Array.isArray(data) ? data : [])
    .map(normalizeQueueItem)
    .filter(item => item.reReviewItemId)
}

export const submitJuryCandidate = async (
  client,
  reReviewItemId,
  payload,
  options = {}
) => callRpc(client, 'submit_jury_candidate', {
  p_re_review_item_id: reReviewItemId,
  p_payload: payload
}, options)

export const castJuryVote = async (client, candidateId, vote, options = {}) => (
  callRpc(client, 'cast_jury_vote', {
    p_candidate_id: candidateId,
    p_vote: vote
  }, options)
)

export const rejectJuryCandidateAsAdmin = async (
  client,
  candidateId,
  reason,
  options = {}
) => callRpc(client, 'admin_reject_jury_candidate', {
  p_candidate_id: candidateId,
  p_reason: reason
}, options)
