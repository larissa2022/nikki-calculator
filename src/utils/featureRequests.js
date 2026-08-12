export const FEATURE_REQUEST_FILTER = Object.freeze({
  PENDING: 'pending',
  PLANNED: 'planned',
  NOT_FEASIBLE: 'not_feasible'
})

const ADMIN_ACTIONS = Object.freeze({
  plan: { label: '计划中', confirmLabel: '确认标记为计划中', publicResponse: 'optional' },
  not_feasible: { label: '技术无法实现', confirmLabel: '确认标记为技术无法实现', publicResponse: 'required' },
  reopen: { label: '重新评估', confirmLabel: '确认恢复待评估' },
  mark_duplicate: { label: '重复归档', confirmLabel: '确认归档为重复建议', duplicateTarget: true },
  hide: { label: '隐藏', confirmLabel: '确认隐藏建议' },
  restore: { label: '恢复公开', confirmLabel: '确认恢复公开' }
})

const action = value => ({ value, ...ADMIN_ACTIONS[value] })

export const availableFeatureRequestAdminActions = item => {
  if (item?.visibility === 'hidden' || item?.visibility === 'duplicate') return [action('restore')]
  if (item?.visibility !== 'public') return []
  if (item?.status === FEATURE_REQUEST_FILTER.PENDING) {
    return [action('plan'), action('not_feasible'), action('mark_duplicate'), action('hide')]
  }
  return [action('reopen'), action('hide')]
}

export const featureRequestAdminAction = value => ADMIN_ACTIONS[value]

export const validateFeatureRequestAdminDecision = ({ action: actionValue, reason, publicResponse, duplicateOf }) => {
  const actionConfig = featureRequestAdminAction(actionValue)
  if (!actionConfig) return '请先选择处理动作。'
  if (String(reason || '').trim().length < 2) return '请填写至少 2 个字的内部处理记录。'
  if (actionConfig.publicResponse === 'required' && !String(publicResponse || '').trim()) {
    return '技术无法实现必须填写给用户看的公开说明。'
  }
  if (actionConfig.duplicateTarget && !String(duplicateOf || '').trim()) return '请选择重复的原建议。'
  return ''
}

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
