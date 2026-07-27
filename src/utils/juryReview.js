import { GRADE_OPTIONS, SCORE_MATRIX, getBroadCategory } from '../composables/useScoreEngine.js'
import { ATTRIBUTE_PAIRS, createClothesEntryFormState, normalizeClothingTags } from './gameConstants.js'
import { buildClothingScoresFromForm } from './clothingScores.js'

export const JURY_FIELD_LABELS = {
  name: '服装名称',
  game_id: '短编号',
  category: '分类部位',
  stars: '星级',
  pair1: '第一组属性',
  pair2: '第二组属性',
  pair3: '第三组属性',
  pair4: '第四组属性',
  pair5: '第五组属性',
  suit: '所属套装',
  tags: '特殊标签'
}

const findGrade = (category, score) => {
  const matrix = SCORE_MATRIX[getBroadCategory(category)] || SCORE_MATRIX['饰品']
  return GRADE_OPTIONS.find(grade => Number(matrix[grade]) === Number(score)) || '完美'
}

export const createJuryCandidateForm = (payload = {}) => {
  const category = String(payload.category || '发型')
  const scores = payload.scores && typeof payload.scores === 'object' ? payload.scores : {}
  const form = createClothesEntryFormState({
    name: String(payload.name || ''),
    game_id: String(payload.game_id || ''),
    category,
    stars: Number(payload.stars) || 5,
    tags: String(payload.tags || ''),
    suit_id: String(payload.suit_id || ''),
    suit_status: payload.suit_id ? 'existing' : 'none'
  })

  ATTRIBUTE_PAIRS.forEach(pair => {
    const selected = pair.options.find(option => Number(scores[option.value]) > 0)
      || pair.options[0]
    form[pair.key] = selected.value
    form[pair.gradeKey] = findGrade(category, scores[selected.value])
  })

  return form
}

export const buildJuryCandidatePayload = form => ({
  name: String(form.name || '').trim(),
  game_id: String(form.game_id || '').trim(),
  category: String(form.category || '').trim(),
  stars: Number(form.stars),
  scores: buildClothingScoresFromForm(form.category, form),
  suit_id: form.suit_status === 'existing' && form.suit_id
    ? String(form.suit_id)
    : null,
  temp_suit_name: null,
  tags: normalizeClothingTags(form.tags) || null,
  needs_suit_review: false
})

export const getReadonlyJuryFields = issues => {
  const editable = new Set((issues || []).map(issue => issue.field))
  const fields = ['name', 'game_id', 'category', 'stars', 'tags', 'suit']
  ATTRIBUTE_PAIRS.forEach((pair, index) => {
    if (!editable.has(`pair${index + 1}`)) {
      fields.push(pair.key, pair.gradeKey)
    }
  })
  return fields.filter(field => !editable.has(field))
}

export const describeJuryIssues = issues => {
  const missing = []
  const conflicts = []
  ;(issues || []).forEach(issue => {
    const label = JURY_FIELD_LABELS[issue.field] || issue.field
    if (issue.kind === 'missing') missing.push(label)
    else conflicts.push(label)
  })
  return { missing, conflicts }
}

export const getCandidateSummary = (payload = {}, suitsById = new Map()) => {
  const suitId = String(payload.suit_id || '')
  return [
    { label: '服装名称', value: payload.name || '未填写' },
    { label: '分类与编号', value: `${payload.category || '未知分类'} · ${payload.game_id || '未知编号'}` },
    { label: '星级', value: payload.stars ? `${payload.stars} 星` : '未填写' },
    {
      label: '所属套装',
      value: suitId ? (suitsById.get(suitId)?.name || `套装 ${suitId}`) : '无关联套装（纯散件）'
    },
    { label: '特殊标签', value: payload.tags || '无' }
  ]
}

export const formatJuryFieldValue = (payload = {}, field, suitsById = new Map()) => {
  if (field === 'suit') {
    const suitId = String(payload.suit_id || '')
    return suitId
      ? (suitsById.get(suitId)?.name || `套装 ${suitId}`)
      : '无关联套装（纯散件）'
  }
  if (field === 'stars') return payload.stars ? `${payload.stars} 星` : '未填写'
  if (field === 'tags') return payload.tags || '无'
  if (field.startsWith('pair')) {
    const pairIndex = Number(field.slice(4)) - 1
    const pair = ATTRIBUTE_PAIRS[pairIndex]
    const scores = payload.scores && typeof payload.scores === 'object' ? payload.scores : {}
    const selected = pair?.options.find(option => Number(scores[option.value]) > 0)
    if (!selected) return '未填写'
    return `${selected.label}（${scores[selected.value]}）`
  }
  return payload[field] ?? '未填写'
}

export const buildJuryVoteUpdate = (result = {}, fallbackVote = '') => {
  const approveCount = Number(result.approve_count)
  const rejectCount = Number(result.reject_count)
  return {
    approveCount: Number.isFinite(approveCount) ? approveCount : null,
    rejectCount: Number.isFinite(rejectCount) ? rejectCount : null,
    myVote: String(result.my_vote || fallbackVote || ''),
    status: String(result.status || 'voting'),
    pointsAwarded: Number(result.points_awarded) === 1 ? 1 : 0
  }
}
