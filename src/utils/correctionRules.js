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
