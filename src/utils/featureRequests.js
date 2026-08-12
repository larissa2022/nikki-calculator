export const FEATURE_REQUEST_FILTER = Object.freeze({
  PENDING: 'pending',
  PLANNED: 'planned',
  NOT_FEASIBLE: 'not_feasible'
})

export const normalizeFeatureRequest = row => ({
  requestId: String(row?.request_id || ''),
  title: String(row?.title || '').trim(),
  description: String(row?.description || '').trim(),
  status: String(row?.status || FEATURE_REQUEST_FILTER.PENDING),
  visibility: String(row?.visibility || 'public'),
  publicResponse: String(row?.public_response || '').trim(),
  likeCount: Math.max(0, Number(row?.like_count) || 0),
  hasLiked: row?.has_liked === true,
  canWithdraw: row?.can_withdraw === true,
  duplicateOf: row?.duplicate_of || null,
  authorId: row?.author_id || null,
  authorName: String(row?.author_name || '').trim(),
  createdAt: row?.created_at || null,
  updatedAt: row?.updated_at || null,
  handledAt: row?.handled_at || null
})
