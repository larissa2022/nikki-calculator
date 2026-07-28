export const CORRECTION_FIELDS = Object.freeze([
  { key: 'name', label: '服装名称' },
  { key: 'game_id', label: '短编号' },
  { key: 'category', label: '分类部位' },
  { key: 'stars', label: '星级' },
  { key: 'scores', label: '属性分值' },
  { key: 'suit', label: '所属套装' },
  { key: 'tags', label: '特殊标签' },
  { key: 'other', label: '其他资料' }
])

const FIELD_LABELS = new Map(CORRECTION_FIELDS.map(field => [field.key, field.label]))

const STATUS_LABELS = new Map([
  ['pending', '等待处理'],
  ['reviewing', '处理中'],
  ['approved', '已确认'],
  ['rejected', '未采纳'],
  ['converted_to_re_review', '已转交复核']
])

export const getCorrectionFieldLabel = fieldKey => FIELD_LABELS.get(fieldKey) || '其他资料'
export const getCorrectionStatusLabel = status => STATUS_LABELS.get(status) || '状态更新中'

export const hasMatchingActiveCorrectionRequest = (requests, payload) => (
  (Array.isArray(requests) ? requests : []).some(item => (
    item.clothesId === payload.clothesId
    && item.fieldKey === payload.fieldKey
    && item.reason === payload.reason
    && String(item.proposedPatch?.[payload.fieldKey] || '') === payload.proposedValue
    && ['pending', 'reviewing'].includes(item.status)
  ))
)

export const filterCorrectionClothes = (wardrobe, query, limit = 20) => {
  const keyword = String(query || '').trim().toLocaleLowerCase('zh-CN')
  if (!keyword) return []

  return (Array.isArray(wardrobe) ? wardrobe : [])
    .filter(item => [item?.name, item?.game_id, item?.category]
      .some(value => String(value || '').toLocaleLowerCase('zh-CN').includes(keyword)))
    .slice(0, Math.max(0, limit))
}

export const getCorrectionCurrentValue = (clothes, fieldKey) => {
  if (!clothes) return '请先选择服装'
  if (fieldKey === 'suit') {
    return clothes.suit_name || clothes.temp_suit_name || '无关联套装'
  }
  if (fieldKey === 'scores') {
    const scores = clothes.scores && typeof clothes.scores === 'object' ? clothes.scores : {}
    const entries = Object.entries(scores)
    return entries.length
      ? entries.map(([key, value]) => `${key} ${value}`).join('、')
      : '未记录'
  }
  if (fieldKey === 'other') return '请在下方说明具体资料'

  const value = clothes[fieldKey]
  return value === null || value === undefined || String(value).trim() === ''
    ? '未记录'
    : String(value)
}

const SCORE_FIELDS = Object.freeze([
  'simple', 'gorgeous', 'active', 'elegant', 'cute',
  'mature', 'pure', 'sexy', 'cool', 'warm'
])

const SCORE_PAIRS = Object.freeze([
  ['simple', 'gorgeous'],
  ['active', 'elegant'],
  ['cute', 'mature'],
  ['pure', 'sexy'],
  ['cool', 'warm']
])

export const createCorrectionReviewDraft = item => {
  const fieldKey = String(item?.fieldKey || '')
  const proposedValue = item?.proposedPatch?.[fieldKey]
  const baseScores = item?.basePayload?.scores && typeof item.basePayload.scores === 'object'
    ? item.basePayload.scores
    : {}

  return {
    value: ['name', 'game_id', 'category', 'tags'].includes(fieldKey)
      ? String(proposedValue ?? '')
      : '',
    stars: Number(proposedValue) || Number(item?.basePayload?.stars) || 5,
    scores: Object.fromEntries(SCORE_FIELDS.map(key => [key, Number(baseScores[key]) || 0])),
    suitId: '',
    noSuit: false,
    resolutionNote: ''
  }
}

export const buildCorrectionAcceptedValue = (fieldKey, draft = {}) => {
  if (['name', 'game_id', 'category'].includes(fieldKey)) {
    return String(draft.value || '').trim()
  }
  if (fieldKey === 'stars') return Number(draft.stars)
  if (fieldKey === 'scores') {
    return Object.fromEntries(SCORE_FIELDS.map(key => [key, Number(draft.scores?.[key]) || 0]))
  }
  if (fieldKey === 'suit') {
    return {
      suit_id: draft.noSuit ? null : (String(draft.suitId || '').trim() || null),
      temp_suit_name: null,
      needs_suit_review: false
    }
  }
  if (fieldKey === 'tags') {
    const value = String(draft.value || '').trim()
    return value || null
  }
  return null
}

export const validateCorrectionReview = (fieldKey, draft = {}, action = '') => {
  const noteLength = String(draft.resolutionNote || '').trim().length
  if (noteLength < 10 || noteLength > 1000) return '请用 10 到 1000 个字填写处理说明。'
  if (action === 'reject') return ''
  if (fieldKey === 'other') return '“其他资料”只能不采纳，请让用户针对具体字段重新提交。'

  const acceptedValue = buildCorrectionAcceptedValue(fieldKey, draft)
  if (['name', 'category'].includes(fieldKey) && (!acceptedValue || acceptedValue.length > 200)) {
    return '请填写 1 到 200 个字的核对结果。'
  }
  if (fieldKey === 'game_id' && !/^\d{1,30}$/.test(acceptedValue)) {
    return '短编号必须是 1 到 30 位数字。'
  }
  if (fieldKey === 'stars' && (!Number.isInteger(acceptedValue) || acceptedValue < 1 || acceptedValue > 6)) {
    return '星级必须是 1 到 6 的整数。'
  }
  if (fieldKey === 'scores') {
    const complete = SCORE_PAIRS.every(([left, right]) => {
      const leftValue = acceptedValue[left]
      const rightValue = acceptedValue[right]
      return (leftValue > 0 && rightValue === 0) || (rightValue > 0 && leftValue === 0)
    })
    if (!complete) return '每组属性必须一项大于 0，另一项为 0。'
  }
  if (fieldKey === 'suit' && !draft.noSuit && !String(draft.suitId || '').trim()) {
    return '请选择已有套装，或明确选择无关联套装。'
  }
  if (fieldKey === 'tags' && String(draft.value || '').trim().length > 500) {
    return '特殊标签不能超过 500 个字。'
  }
  return ''
}

export const formatCorrectionReviewValue = (value, fieldKey, suitsById = new Map()) => {
  if (fieldKey === 'suit') {
    const suitId = String(value?.suit_id || '')
    return suitId ? (suitsById.get(suitId)?.name || `套装 ${suitId}`) : '无关联套装'
  }
  if (fieldKey === 'scores') {
    if (!value || typeof value !== 'object') return '未记录'
    return SCORE_PAIRS.map(([left, right]) => {
      const selected = Number(value[left]) > 0 ? left : right
      return `${selected} ${value[selected] ?? 0}`
    }).join('、')
  }
  if (fieldKey === 'tags') return value || '无'
  return value === null || value === undefined || value === '' ? '未记录' : String(value)
}
