const normalizeQueueItem = (row) => ({
  reReviewItemId: String(row?.re_review_item_id || ''),
  reason: String(row?.reason || ''),
  itemStatus: String(row?.item_status || 'pending'),
  clothesId: String(row?.clothes_id || ''),
  clothesName: String(row?.clothes_name || '未命名服装'),
  category: String(row?.category || ''),
  gameId: String(row?.game_id || ''),
  candidateId: row?.candidate_id ? String(row.candidate_id) : '',
  candidatePayload: row?.candidate_payload && typeof row.candidate_payload === 'object'
    ? row.candidate_payload
    : null,
  candidateStatus: row?.candidate_status ? String(row.candidate_status) : '',
  candidateCreatedAt: row?.candidate_created_at || null,
  approveCount: Number(row?.approve_count) || 0,
  rejectCount: Number(row?.reject_count) || 0,
  myVote: row?.my_vote ? String(row.my_vote) : '',
  canSubmitCandidate: Boolean(row?.can_submit_candidate),
  canVote: Boolean(row?.can_vote),
  isCandidateAuthor: Boolean(row?.is_candidate_author)
})

const callRpc = async (client, name, params = {}) => {
  if (!client) throw new Error('缺少陪审团查询客户端')
  const { data, error } = await client.rpc(name, params)
  if (error) throw error
  return data
}

export const fetchJuryReviewQueue = async (client) => {
  const data = await callRpc(client, 'get_jury_review_queue')
  return (Array.isArray(data) ? data : [])
    .map(normalizeQueueItem)
    .filter(item => item.reReviewItemId)
}

export const submitJuryCandidate = async (client, reReviewItemId, suitId) => (
  callRpc(client, 'submit_jury_candidate', {
    p_re_review_item_id: reReviewItemId,
    p_payload: { suit_id: suitId }
  })
)

export const castJuryVote = async (client, candidateId, vote) => (
  callRpc(client, 'cast_jury_vote', {
    p_candidate_id: candidateId,
    p_vote: vote
  })
)

export const rejectJuryCandidateAsAdmin = async (client, candidateId, reason) => (
  callRpc(client, 'admin_reject_jury_candidate', {
    p_candidate_id: candidateId,
    p_reason: reason
  })
)
