export const CORRECTION_REQUEST_TIMEOUT_MS = 15000

const createTimeoutError = () => {
  const error = new Error('请求等待时间过长，提交结果可能已经生效，正在重新读取。')
  error.code = 'CORRECTION_REQUEST_TIMEOUT'
  error.isTimeout = true
  return error
}

export const isCorrectionResultUncertain = error => {
  if (error?.isTimeout) return true
  const message = String(error?.message || error || '')
  return /failed to fetch|network|load failed|connection|socket|econn/i.test(message)
}

export const createCorrectionRequestGate = () => {
  let currentRequestId = 0
  return {
    next: () => ++currentRequestId,
    invalidate: () => { currentRequestId += 1 },
    isCurrent: requestId => requestId === currentRequestId
  }
}

export const withCorrectionRequestTimeout = async (
  requestFactory,
  { timeoutMs = CORRECTION_REQUEST_TIMEOUT_MS, signal } = {}
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

const callRpc = async (client, name, params = {}, options = {}) => {
  if (!client) throw new Error('缺少图鉴报错服务')

  return withCorrectionRequestTimeout(async signal => {
    let request = client.rpc(name, params)
    if (typeof request?.abortSignal === 'function') request = request.abortSignal(signal)
    const { data, error } = await request
    if (error) throw error
    return data
  }, options)
}

export const normalizeCorrectionRequest = row => ({
  requestId: String(row?.request_id || ''),
  clothesId: String(row?.clothes_id || ''),
  clothesName: String(row?.clothes_name || '未命名服装'),
  gameId: String(row?.game_id || ''),
  category: String(row?.category || ''),
  fieldKey: String(row?.field_key || ''),
  reason: String(row?.reason || ''),
  proposedPatch: row?.proposed_patch && typeof row.proposed_patch === 'object'
    ? row.proposed_patch
    : {},
  status: String(row?.status || 'pending'),
  resolutionNote: String(row?.resolution_note || ''),
  createdAt: row?.created_at || null,
  updatedAt: row?.updated_at || null
})

export const normalizeCorrectionReviewItem = row => ({
  requestId: String(row?.request_id || ''),
  clothesId: String(row?.clothes_id || ''),
  clothesName: String(row?.clothes_name || '未命名服装'),
  gameId: String(row?.game_id || ''),
  category: String(row?.category || ''),
  fieldKey: String(row?.field_key || ''),
  reason: String(row?.reason || ''),
  proposedPatch: row?.proposed_patch && typeof row.proposed_patch === 'object'
    ? row.proposed_patch
    : {},
  basePayload: row?.base_payload && typeof row.base_payload === 'object'
    ? row.base_payload
    : {},
  currentValue: row?.current_value ?? null,
  reporterName: String(row?.reporter_name || '已注销用户'),
  createdAt: row?.created_at || null,
  isOwnRequest: Boolean(row?.is_own_request),
  canReview: Boolean(row?.can_review),
  canApproveDirectly: Boolean(row?.can_approve_directly),
  canSendToJury: Boolean(row?.can_send_to_jury)
})

export const fetchMyCorrectionRequests = async (client, options = {}) => {
  const data = await callRpc(client, 'get_my_correction_requests', {}, options)
  return (Array.isArray(data) ? data : [])
    .map(normalizeCorrectionRequest)
    .filter(item => item.requestId)
}

export const submitCorrectionRequest = (
  client,
  { clothesId, fieldKey, proposedValue, reason },
  options = {}
) => callRpc(client, 'submit_correction_request', {
  p_clothes_id: clothesId,
  p_reason: reason,
  p_proposed_patch: { [fieldKey]: proposedValue }
}, options)

export const fetchCorrectionReviewQueue = async (client, options = {}) => {
  const data = await callRpc(client, 'get_correction_review_queue', {}, options)
  return (Array.isArray(data) ? data : [])
    .map(normalizeCorrectionReviewItem)
    .filter(item => item.requestId)
}

export const reviewCorrectionRequest = (
  client,
  { requestId, action, acceptedValue = null, resolutionNote },
  options = {}
) => callRpc(client, 'review_correction_request', {
  p_request_id: requestId,
  p_action: action,
  p_accepted_value: acceptedValue,
  p_resolution_note: resolutionNote
}, options)
