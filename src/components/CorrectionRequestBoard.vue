<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { supabase } from '../api/supabase'
import {
  createCorrectionRequestGate,
  fetchMyCorrectionRequests,
  isCorrectionResultUncertain,
  submitCorrectionRequest
} from '../api/correctionService'
import {
  CORRECTION_FIELDS,
  CORRECTION_OPTION_FIELDS,
  correctionValuesMatch,
  filterCorrectionClothes,
  getCorrectionCurrentValue,
  getCorrectionCurrentProposalValue,
  getCorrectionScoreProposal,
  getCorrectionFieldLabel,
  getCorrectionStatusLabel,
  hasMatchingActiveCorrectionRequest
} from '../utils/correctionRules'
import { ATTRIBUTE_PAIRS, FULL_CATEGORIES } from '../utils/gameConstants'
import { GRADE_OPTIONS } from '../composables/useScoreEngine'
import { buildClothingScoresFromForm } from '../utils/clothingScores'
import { createJuryCandidateForm } from '../utils/juryReview'

const props = defineProps({
  isLoggedIn: Boolean,
  wardrobe: { type: Array, required: true }
})

const searchQuery = ref('')
const selectedClothes = ref(null)
const fieldKey = ref('name')
const useManualInput = ref(false)
const proposalTextValue = ref('')
const proposalCategory = ref('')
const proposalStars = ref(1)
const proposalSuitId = ref('none')
const proposalScoreForm = ref(createJuryCandidateForm())
const changedScorePairIndexes = ref([])
const reason = ref('')
const requests = ref([])
const isLoading = ref(false)
const isSubmitting = ref(false)
const loadError = ref('')
const notice = ref(null)
const loadGate = createCorrectionRequestGate()
let activeLoadController = null
let activeSubmitController = null

const searchResults = computed(() => (
  selectedClothes.value ? [] : filterCorrectionClothes(props.wardrobe, searchQuery.value)
))
const availableSuits = computed(() => {
  const unique = new Map()
  props.wardrobe.forEach(item => {
    if (item?.suit_id && item?.suit_name) {
      unique.set(String(item.suit_id), { id: String(item.suit_id), name: item.suit_name })
    }
  })
  return [...unique.values()].sort((left, right) => left.name.localeCompare(right.name, 'zh-CN'))
})
const hasOptionInput = computed(() => CORRECTION_OPTION_FIELDS.includes(fieldKey.value))
const currentValue = computed(() => getCorrectionCurrentValue(selectedClothes.value, fieldKey.value))
const currentProposalValue = computed(() => getCorrectionCurrentProposalValue(selectedClothes.value, fieldKey.value))
const proposedValue = computed(() => {
  if (useManualInput.value || !hasOptionInput.value) return proposalTextValue.value.trim()
  if (fieldKey.value === 'category') return proposalCategory.value
  if (fieldKey.value === 'stars') return Number(proposalStars.value)
  if (fieldKey.value === 'scores') {
    return getCorrectionScoreProposal(
      currentProposalValue.value,
      buildClothingScoresFromForm(proposalScoreForm.value.category, proposalScoreForm.value),
      changedScorePairIndexes.value
    )
  }
  if (fieldKey.value === 'suit') {
    return {
      suit_id: proposalSuitId.value === 'none' ? null : proposalSuitId.value,
      temp_suit_name: null,
      needs_suit_review: false
    }
  }
  return proposalTextValue.value.trim()
})
const proposalHasValue = computed(() => {
  if (useManualInput.value || !hasOptionInput.value) {
    return proposalTextValue.value.trim().length >= 1 && proposalTextValue.value.trim().length <= 500
  }
  if (fieldKey.value === 'scores') {
    return changedScorePairIndexes.value.length > 0
      ? Boolean(proposalScoreForm.value?.category)
      : currentProposalValue.value !== null
  }
  return proposedValue.value !== null && proposedValue.value !== undefined && proposedValue.value !== ''
})
const proposalChanged = computed(() => !correctionValuesMatch(proposedValue.value, currentProposalValue.value))
const canSubmit = computed(() => (
  props.isLoggedIn
  && selectedClothes.value
  && proposalHasValue.value
  && proposalChanged.value
  && reason.value.trim().length >= 10
  && reason.value.trim().length <= 1000
  && !isSubmitting.value
))

const resetProposal = () => {
  const clothes = selectedClothes.value
  const current = getCorrectionCurrentProposalValue(clothes, fieldKey.value)
  useManualInput.value = false
  proposalTextValue.value = current === null || typeof current === 'object' ? '' : String(current)
  proposalCategory.value = String(clothes?.category || FULL_CATEGORIES[0] || '')
  proposalStars.value = Number(clothes?.stars) || 1
  proposalSuitId.value = clothes?.suit_id ? String(clothes.suit_id) : 'none'
  proposalScoreForm.value = createJuryCandidateForm(clothes || {})
  changedScorePairIndexes.value = []
}

const markScorePairChanged = index => {
  if (changedScorePairIndexes.value.includes(index)) return
  changedScorePairIndexes.value = [...changedScorePairIndexes.value, index]
}

const selectClothes = item => {
  selectedClothes.value = item
  searchQuery.value = `${item.name || '未命名服装'}${item.game_id ? ` #${item.game_id}` : ''}`
  resetProposal()
  notice.value = null
}

const clearSelection = () => {
  selectedClothes.value = null
  searchQuery.value = ''
  proposalTextValue.value = ''
  notice.value = null
}

const loadRequests = async ({ background = false } = {}) => {
  if (!props.isLoggedIn) {
    requests.value = []
    loadError.value = ''
    return
  }

  activeLoadController?.abort()
  activeLoadController = new AbortController()
  const requestId = loadGate.next()
  if (!background) isLoading.value = true
  loadError.value = ''

  try {
    const rows = await fetchMyCorrectionRequests(supabase, {
      signal: activeLoadController.signal
    })
    if (!loadGate.isCurrent(requestId)) return
    requests.value = rows
    return rows
  } catch (error) {
    if (!loadGate.isCurrent(requestId) || error?.name === 'AbortError') return
    console.error('读取本人图鉴报错失败:', error)
    loadError.value = '报错记录暂时无法读取，请稍后重试。'
  } finally {
    if (loadGate.isCurrent(requestId)) isLoading.value = false
  }
}

const submitReport = async () => {
  if (!canSubmit.value) return

  activeSubmitController?.abort()
  activeSubmitController = new AbortController()
  isSubmitting.value = true
  notice.value = null

  const payload = {
    clothesId: selectedClothes.value.id,
    fieldKey: fieldKey.value,
    proposedValue: proposedValue.value,
    reason: reason.value.trim()
  }

  try {
    const result = await submitCorrectionRequest(supabase, payload, {
      signal: activeSubmitController.signal
    })
    notice.value = {
      type: 'success',
      message: result?.idempotent
        ? '这条报错之前已经提交，现有记录保持不变。'
        : '报错已提交，并已直接转交陪审团。'
    }
    resetProposal()
    reason.value = ''
    await loadRequests({ background: true })
  } catch (error) {
    if (error?.name === 'AbortError') return
    if (isCorrectionResultUncertain(error)) {
      notice.value = {
        type: 'warning',
        message: '网络响应中断，正在从数据库确认是否已经提交。请不要重复填写。'
      }
      const confirmedRows = await loadRequests({ background: true })
      const confirmed = hasMatchingActiveCorrectionRequest(confirmedRows, payload)
      if (confirmed) {
        notice.value = {
          type: 'success',
          message: '已从数据库确认报错提交成功，并已直接转交陪审团。'
        }
        resetProposal()
        reason.value = ''
      }
    } else {
      notice.value = {
        type: 'error',
        message: error?.message || '报错提交失败，请稍后重试。'
      }
    }
  } finally {
    isSubmitting.value = false
  }
}

const formatDate = value => {
  if (!value) return '时间未知'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '时间未知'
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date)
}

const proposedText = item => {
  const value = item.proposedPatch?.[item.fieldKey]
  if (value && typeof value === 'object') return JSON.stringify(value)
  return String(value ?? '')
}

watch([selectedClothes, fieldKey], () => {
  if (selectedClothes.value) resetProposal()
})

watch(() => props.isLoggedIn, isLoggedIn => {
  if (isLoggedIn) loadRequests()
  else {
    activeLoadController?.abort()
    activeSubmitController?.abort()
    loadGate.invalidate()
    requests.value = []
  }
}, { immediate: true })

onBeforeUnmount(() => {
  activeLoadController?.abort()
  activeSubmitController?.abort()
  loadGate.invalidate()
})
</script>

<template>
  <section class="correction-board" aria-labelledby="correction-title">
    <header class="board-header">
      <div>
        <p class="eyebrow">正式图鉴纠错</p>
        <h2 id="correction-title">报告资料问题</h2>
        <p>选择错误项目并改成你认为正确的内容。提交后会直接进入陪审团，不需要等待管理员转交。</p>
      </div>
    </header>

    <div v-if="!isLoggedIn" class="state-card">
      <strong>请先登录</strong>
      <span>登录后才能提交报错并查看自己的处理进度。</span>
    </div>

    <template v-else>
      <form class="report-form" @submit.prevent="submitReport">
        <div class="form-section">
          <label for="correction-search">1. 查找需要报错的服装</label>
          <div class="search-row">
            <input
              id="correction-search"
              v-model="searchQuery"
              type="search"
              autocomplete="off"
              placeholder="输入服装名称、短编号或分类"
              :readonly="Boolean(selectedClothes)"
              @input="selectedClothes = null"
            />
            <button v-if="selectedClothes" type="button" class="secondary-btn" @click="clearSelection">重新选择</button>
          </div>

          <div v-if="searchQuery.trim() && !selectedClothes" class="search-results" role="listbox" aria-label="匹配的正式服装">
            <button
              v-for="item in searchResults"
              :key="item.id"
              type="button"
              role="option"
              @click="selectClothes(item)"
            >
              <strong>{{ item.name || '未命名服装' }}</strong>
              <span>{{ item.category || '分类未记录' }} · {{ item.game_id ? `#${item.game_id}` : '短编号未记录' }}</span>
            </button>
            <p v-if="searchResults.length === 0">没有找到匹配服装，请先确认正式图鉴是否已经收录。</p>
          </div>
        </div>

        <template v-if="selectedClothes">
          <div class="selected-card">
            <div>
              <strong>{{ selectedClothes.name || '未命名服装' }}</strong>
              <span>{{ selectedClothes.category || '分类未记录' }} · {{ selectedClothes.game_id ? `#${selectedClothes.game_id}` : '短编号未记录' }}</span>
            </div>
            <span class="selected-badge">已选择</span>
          </div>

          <div class="form-section">
            <label>
              <span>2. 哪项资料有问题</span>
              <select v-model="fieldKey">
                <option v-for="field in CORRECTION_FIELDS" :key="field.key" :value="field.key">{{ field.label }}</option>
              </select>
            </label>
          </div>

          <div class="form-section">
            <div class="proposal-heading">
              <label for="correction-proposal">3. 改成正确内容</label>
              <button
                v-if="hasOptionInput"
                type="button"
                class="manual-toggle"
                @click="useManualInput = !useManualInput"
              >
                {{ useManualInput ? '返回选项' : '没有选项？改为手动输入' }}
              </button>
            </div>

            <div class="current-value">
              <span>图鉴当前值（下方已默认带入）</span>
              <strong>{{ currentValue }}</strong>
            </div>

            <input
              v-if="useManualInput || !hasOptionInput"
              id="correction-proposal"
              v-model="proposalTextValue"
              type="text"
              maxlength="500"
              placeholder="填写正确内容"
            />

            <select v-else-if="fieldKey === 'category'" v-model="proposalCategory" id="correction-proposal">
              <option v-for="category in FULL_CATEGORIES" :key="category" :value="category">{{ category }}</option>
            </select>

            <select v-else-if="fieldKey === 'stars'" v-model.number="proposalStars" id="correction-proposal">
              <option v-for="stars in 6" :key="stars" :value="stars">{{ stars }} 星</option>
            </select>

            <div v-else-if="fieldKey === 'scores'" id="correction-proposal" class="score-options">
              <div v-for="(pair, index) in ATTRIBUTE_PAIRS" :key="pair.key" class="score-row">
                <select v-model="proposalScoreForm[pair.key]" @change="markScorePairChanged(index)">
                  <option v-for="option in pair.options" :key="option.value" :value="option.value">{{ option.label }}</option>
                </select>
                <select v-model="proposalScoreForm[pair.gradeKey]" @change="markScorePairChanged(index)">
                  <option v-for="grade in GRADE_OPTIONS" :key="grade" :value="grade">{{ grade }}</option>
                </select>
              </div>
            </div>

            <select v-else-if="fieldKey === 'suit'" v-model="proposalSuitId" id="correction-proposal">
              <option value="none">无关联套装（纯散件）</option>
              <option v-for="suit in availableSuits" :key="suit.id" :value="suit.id">《{{ suit.name }}》</option>
            </select>

            <p class="proposal-help" :class="{ invalid: proposalHasValue && !proposalChanged }">
              {{ proposalHasValue && !proposalChanged ? '请把默认值改成正确内容后再提交。' : '提交后由其他用户补充完整资料并投票审核。' }}
            </p>
            <span v-if="useManualInput || !hasOptionInput" class="counter">{{ proposalTextValue.trim().length }} / 500</span>
          </div>

          <div class="form-section">
            <label for="correction-reason">4. 为什么这样判断</label>
            <textarea
              id="correction-reason"
              v-model="reason"
              maxlength="1000"
              rows="4"
              placeholder="至少 10 个字，例如游戏内查看位置、截图内容或可核对的依据"
            />
            <span class="counter" :class="{ invalid: reason.trim().length > 0 && reason.trim().length < 10 }">
              {{ reason.trim().length }} / 1000（至少 10 个字）
            </span>
          </div>

          <div v-if="notice" class="notice" :class="notice.type" role="status">{{ notice.message }}</div>

          <button type="submit" class="primary-btn" :disabled="!canSubmit">
            {{ isSubmitting ? '正在提交并转交…' : '提交并转交陪审团' }}
          </button>
        </template>
      </form>

      <section class="history-section" aria-labelledby="my-corrections-title">
        <div class="history-header">
          <div>
            <p class="eyebrow">只对你可见</p>
            <h3 id="my-corrections-title">我的报错记录</h3>
          </div>
          <button type="button" class="secondary-btn" :disabled="isLoading" @click="loadRequests()">刷新</button>
        </div>

        <div v-if="isLoading" class="state-card"><strong>正在读取报错记录…</strong></div>
        <div v-else-if="loadError" class="state-card error-state">
          <strong>{{ loadError }}</strong>
          <button type="button" class="secondary-btn" @click="loadRequests()">重新读取</button>
        </div>
        <div v-else-if="requests.length === 0" class="state-card">
          <strong>还没有报错记录</strong>
          <span>提交后的进度会显示在这里。</span>
        </div>
        <div v-else class="history-list">
          <article v-for="item in requests" :key="item.requestId" class="history-card">
            <header>
              <div>
                <strong>{{ item.clothesName }}</strong>
                <span>{{ item.category || '分类未记录' }} · {{ item.gameId ? `#${item.gameId}` : '短编号未记录' }}</span>
              </div>
              <span class="status-badge" :class="item.status">{{ getCorrectionStatusLabel(item.status) }}</span>
            </header>
            <dl>
              <div><dt>问题字段</dt><dd>{{ getCorrectionFieldLabel(item.fieldKey) }}</dd></div>
              <div><dt>建议内容</dt><dd>{{ proposedText(item) }}</dd></div>
              <div><dt>判断依据</dt><dd>{{ item.reason }}</dd></div>
              <div v-if="item.resolutionNote"><dt>处理说明</dt><dd>{{ item.resolutionNote }}</dd></div>
            </dl>
            <time :datetime="item.createdAt || undefined">提交于 {{ formatDate(item.createdAt) }}</time>
          </article>
        </div>
      </section>
    </template>
  </section>
</template>

<style scoped>
.correction-board { animation: fadeIn 0.35s ease; }
.board-header { margin-bottom: 18px; }
.eyebrow { margin: 0 0 4px; color: #db2777; font-size: 11px; font-weight: 900; letter-spacing: 0.12em; }
h2, h3 { margin: 0; color: #1e293b; font-weight: 900; }
h2 { font-size: 24px; }
h3 { font-size: 18px; }
.board-header p:last-child { margin: 7px 0 0; color: #64748b; font-size: 13px; font-weight: 600; line-height: 1.7; }
.report-form, .history-section { padding: 18px; border: 1px solid #f1f5f9; border-radius: 18px; background: rgba(255,255,255,0.9); box-shadow: 0 6px 18px rgba(148,163,184,0.08); }
.form-section { position: relative; margin-bottom: 16px; }
.form-section > label, .form-section label > span { display: block; margin-bottom: 7px; color: #475569; font-size: 12px; font-weight: 900; }
.proposal-heading { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 7px; }
.proposal-heading label { color: #475569; font-size: 12px; font-weight: 900; }
.manual-toggle { padding: 0; border: 0; background: transparent; color: #7c3aed; font-size: 11px; font-weight: 900; text-decoration: underline; cursor: pointer; }
input, textarea, select { width: 100%; box-sizing: border-box; padding: 11px 12px; border: 1.5px solid #e2e8f0; border-radius: 11px; background: #fff; color: #334155; font-size: 13px; font-weight: 650; outline: none; }
textarea { resize: vertical; line-height: 1.65; }
input:focus, textarea:focus, select:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244,114,182,0.12); }
.search-row { display: flex; gap: 8px; }
.search-results { position: relative; z-index: 2; display: grid; gap: 6px; max-height: 260px; margin-top: 7px; padding: 7px; overflow: auto; border: 1px solid #f1f5f9; border-radius: 12px; background: #fff; box-shadow: 0 12px 24px rgba(15,23,42,0.1); }
.search-results button { display: flex; justify-content: space-between; gap: 12px; padding: 10px; border: 0; border-radius: 9px; background: #f8fafc; color: #334155; text-align: left; cursor: pointer; }
.search-results button:hover { background: #fdf2f8; }
.search-results span, .selected-card span, .history-card header span { color: #64748b; font-size: 11px; font-weight: 700; }
.search-results p { margin: 10px; color: #64748b; font-size: 12px; }
.selected-card { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 16px; padding: 13px; border: 1px solid #bbf7d0; border-radius: 12px; background: #f0fdf4; }
.selected-card div { display: grid; gap: 3px; }
.selected-badge { padding: 4px 8px; border-radius: 999px; background: #dcfce7; color: #15803d !important; }
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.current-value { padding: 10px 12px; border-radius: 11px; background: #f8fafc; }
.current-value span { display: block; margin-bottom: 5px; color: #94a3b8; font-size: 11px; font-weight: 800; }
.current-value strong { display: block; color: #475569; font-size: 12px; line-height: 1.6; word-break: break-word; }
.proposal-heading + .current-value { margin-bottom: 8px; }
.proposal-help { margin: 7px 0 0; color: #64748b; font-size: 11px; font-weight: 750; line-height: 1.5; }
.proposal-help.invalid { color: #be123c; }
.score-options { display: grid; gap: 8px; }
.score-row { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.counter { display: block; margin-top: 5px; color: #94a3b8; font-size: 10px; font-weight: 700; text-align: right; }
.counter.invalid { color: #e11d48; }
.primary-btn, .secondary-btn { border: 0; border-radius: 10px; font-weight: 900; cursor: pointer; }
.primary-btn { width: 100%; padding: 12px; background: linear-gradient(135deg,#f472b6,#d946ef); color: #fff; box-shadow: 0 5px 15px rgba(244,114,182,0.25); }
.secondary-btn { flex: 0 0 auto; padding: 9px 11px; background: #f1f5f9; color: #64748b; }
.primary-btn:disabled, .secondary-btn:disabled { opacity: 0.55; cursor: not-allowed; }
.notice { margin-bottom: 13px; padding: 10px 12px; border-radius: 10px; font-size: 12px; font-weight: 800; line-height: 1.6; }
.notice.success { background: #ecfdf5; color: #047857; }
.notice.warning { background: #fffbeb; color: #b45309; }
.notice.error, .error-state { background: #fff1f2; color: #be123c; }
.history-section { margin-top: 20px; }
.history-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
.state-card { display: grid; gap: 6px; justify-items: center; padding: 24px; border-radius: 13px; background: #f8fafc; color: #64748b; font-size: 12px; text-align: center; }
.history-list { display: grid; gap: 10px; }
.history-card { padding: 13px; border: 1px solid #f1f5f9; border-radius: 13px; background: #fff; }
.history-card header { display: flex; justify-content: space-between; gap: 12px; }
.history-card header div { display: grid; gap: 3px; }
.status-badge { align-self: start; padding: 4px 8px; border-radius: 999px; background: #fef3c7; color: #b45309 !important; white-space: nowrap; }
.status-badge.approved { background: #dcfce7; color: #15803d !important; }
.status-badge.rejected { background: #ffe4e6; color: #be123c !important; }
.status-badge.reviewing, .status-badge.converted_to_re_review { background: #ede9fe; color: #7c3aed !important; }
dl { display: grid; gap: 7px; margin: 12px 0; }
dl div { display: grid; grid-template-columns: 68px 1fr; gap: 8px; }
dt { color: #94a3b8; font-size: 11px; font-weight: 800; }
dd { margin: 0; color: #475569; font-size: 12px; font-weight: 650; line-height: 1.55; word-break: break-word; }
time { color: #94a3b8; font-size: 10px; font-weight: 700; }
@media (max-width: 640px) {
  .form-grid { grid-template-columns: 1fr; }
  .search-row { align-items: stretch; }
  .search-results button { flex-direction: column; }
  .report-form, .history-section { padding: 14px; }
}
</style>
