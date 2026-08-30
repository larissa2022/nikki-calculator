<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { supabase } from '../api/supabase'
import {
  castJuryVote,
  createJuryRequestGate,
  fetchJuryReviewQueue,
  isJuryResultUncertain,
  rejectJuryCandidateAsAdmin,
  submitJuryCandidate,
  withJuryRequestTimeout
} from '../api/juryService'
import { suitService } from '../api/suitService'
import { createCorrectionEvidenceSignedUrl } from '../api/correctionEvidenceService'
import ClothesEntryForm from './ClothesEntryForm.vue'
import { getJuryStatusText, JURY_VOTE } from '../utils/juryRules'
import {
  buildJuryVoteUpdate,
  buildJuryCandidatePayload,
  buildJuryCandidateSubmissionPayload,
  createJuryCandidateForm,
  formatJuryFieldValue,
  getEditableJuryFields,
  getCandidateSummary,
  JURY_FIELD_LABELS
} from '../utils/juryReview'
import { clampJuryCardIndex, getJurySwipeDirection } from '../utils/juryCarousel'

const props = defineProps({
  isLoggedIn: Boolean,
  canPermanentlyReject: Boolean,
  isSuperAdmin: Boolean
})

const items = ref([])
const suits = ref([])
const candidateForms = ref({})
const suitSearchTexts = ref({})
const adminReasons = ref({})
const reviewNotes = ref({})
const formErrors = ref({})
const activeActions = ref({})
const isLoading = ref(false)
const isRefreshing = ref(false)
const isSuitsLoading = ref(false)
const loadError = ref('')
const notice = ref(null)
const confirmation = ref(null)
const activeCardIndex = ref(0)
const evidenceUrls = ref({})
const evidenceFailures = ref({})
const swipeStart = ref(null)

const queueRequests = createJuryRequestGate()
const suitRequests = createJuryRequestGate()
let loadController = null
let suitController = null
const actionControllers = new Set()

const suitsById = computed(() => new Map(
  suits.value.map(suit => [String(suit.id), suit])
))
const activeItem = computed(() => items.value[activeCardIndex.value] || null)

const moveToCard = index => {
  activeCardIndex.value = clampJuryCardIndex(index, items.value.length)
}

const handleSwipeStart = event => {
  const touch = event.touches?.[0]
  swipeStart.value = touch ? { x: touch.clientX, y: touch.clientY } : null
}

const handleSwipeEnd = event => {
  const touch = event.changedTouches?.[0]
  if (!touch || !swipeStart.value) return
  const direction = getJurySwipeDirection({
    startX: swipeStart.value.x,
    startY: swipeStart.value.y,
    endX: touch.clientX,
    endY: touch.clientY
  })
  swipeStart.value = null
  if (direction === 'next') moveToCard(activeCardIndex.value + 1)
  if (direction === 'previous') moveToCard(activeCardIndex.value - 1)
}

const loadEvidenceUrls = async (queue, queueRequestId) => {
  const paths = [...new Set(queue.flatMap(item => (
    item.correctionEvidence.map(evidence => evidence.path)
  )))].filter(path => !evidenceUrls.value[path] && !evidenceFailures.value[path])
  if (!paths.length) return

  const results = await Promise.allSettled(paths.map(path => (
    createCorrectionEvidenceSignedUrl(supabase, path)
  )))
  if (!queueRequests.isCurrent(queueRequestId)) return

  const nextUrls = { ...evidenceUrls.value }
  const nextFailures = { ...evidenceFailures.value }
  results.forEach((result, index) => {
    const path = paths[index]
    if (result.status === 'fulfilled' && result.value) nextUrls[path] = result.value
    else nextFailures[path] = true
  })
  evidenceUrls.value = nextUrls
  evidenceFailures.value = nextFailures
}

const setFormError = (itemId, message = '') => {
  formErrors.value = { ...formErrors.value, [itemId]: message }
}

const setActionActive = (key, active) => {
  const next = { ...activeActions.value }
  if (active) next[key] = true
  else delete next[key]
  activeActions.value = next
}

const isActionActive = key => Boolean(activeActions.value[key])
const isItemBusy = item => Object.keys(activeActions.value)
  .some(key => key.endsWith(item.reReviewItemId) || key.endsWith(item.candidateId))

const initializeCandidateForms = queue => {
  const nextForms = { ...candidateForms.value }
  const nextSearchTexts = { ...suitSearchTexts.value }

  queue.forEach(item => {
    if (!item.canSubmitCandidate || nextForms[item.reReviewItemId]) return
    const form = createJuryCandidateForm(item.basePayload, item.issues)
    nextForms[item.reReviewItemId] = form
    const suitName = item.baseSuitName
      || suitsById.value.get(String(form.suit_id))?.name
      || ''
    nextSearchTexts[item.reReviewItemId] = form.suit_id && suitName
      ? `《${suitName}》`
      : ''
  })

  candidateForms.value = nextForms
  suitSearchTexts.value = nextSearchTexts
}

const needsSuitRows = queue => queue.some(item => (
  item.issues.some(issue => issue.field === 'suit')
))

const loadSuits = async queueRequestId => {
  if (suits.value.length) return
  const requestId = suitRequests.next()
  suitController?.abort()
  const controller = new AbortController()
  suitController = controller
  isSuitsLoading.value = true
  try {
    const rows = await withJuryRequestTimeout(
      requestSignal => suitService.getAllSuits({ signal: requestSignal }),
      { signal: controller.signal }
    )
    if (!suitRequests.isCurrent(requestId) || !queueRequests.isCurrent(queueRequestId)) return
    suits.value = rows
    const nextSearchTexts = { ...suitSearchTexts.value }
    Object.entries(candidateForms.value).forEach(([itemId, form]) => {
      if (!form?.suit_id) return
      const suitName = suitsById.value.get(String(form.suit_id))?.name
      if (suitName) nextSearchTexts[itemId] = `《${suitName}》`
    })
    suitSearchTexts.value = nextSearchTexts
    initializeCandidateForms(items.value)
  } catch (error) {
    if (controller.signal.aborted || !suitRequests.isCurrent(requestId)) return
    console.error('加载套装列表失败:', error)
    notice.value = {
      tone: 'warning',
      message: '审核事项已加载，但套装列表暂时不可用。可以稍后重试刷新。'
    }
  } finally {
    if (suitRequests.isCurrent(requestId)) isSuitsLoading.value = false
  }
}

const loadQueue = async ({ background = false } = {}) => {
  if (!props.isLoggedIn) {
    loadController?.abort()
    suitController?.abort()
    queueRequests.invalidate()
    suitRequests.invalidate()
    items.value = []
    isLoading.value = false
    isRefreshing.value = false
    isSuitsLoading.value = false
    return
  }

  const requestId = queueRequests.next()
  loadController?.abort()
  const controller = new AbortController()
  loadController = controller
  const hasExistingItems = items.value.length > 0
  isLoading.value = !background && !hasExistingItems
  isRefreshing.value = background || hasExistingItems
  loadError.value = ''

  try {
    const queue = await fetchJuryReviewQueue(supabase, {
      signal: controller.signal
    })
    if (!queueRequests.isCurrent(requestId)) return

    items.value = queue
    activeCardIndex.value = clampJuryCardIndex(activeCardIndex.value, queue.length)
    initializeCandidateForms(queue)
    void loadEvidenceUrls(queue, requestId)
    if (needsSuitRows(queue)) {
      void loadSuits(requestId)
    } else {
      suitController?.abort()
      suitRequests.invalidate()
      isSuitsLoading.value = false
    }
  } catch (error) {
    if (controller.signal.aborted || !queueRequests.isCurrent(requestId)) return
    console.error('加载陪审团失败:', error)
    const message = error?.message || '陪审团暂时无法加载'
    if (hasExistingItems) {
      notice.value = { tone: 'warning', message: `刷新失败，页面保留了现有内容：${message}` }
    } else {
      loadError.value = message
    }
  } finally {
    if (queueRequests.isCurrent(requestId)) {
      isLoading.value = false
      isRefreshing.value = false
    }
  }
}

const runAction = async ({ key, item, action, onSuccess, successMessage }) => {
  if (isActionActive(key)) return
  const controller = new AbortController()
  actionControllers.add(controller)
  setActionActive(key, true)
  setFormError(item.reReviewItemId)

  const applySuccess = result => {
    onSuccess?.(result)
    notice.value = { tone: 'success', message: successMessage(result) }
    void loadQueue({ background: true })
  }

  try {
    const result = await action(controller.signal)
    applySuccess(result)
  } catch (error) {
    if (controller.signal.aborted) return
    console.error('陪审团操作失败:', error)
    if (isJuryResultUncertain(error)) {
      notice.value = {
        tone: 'warning',
        message: '操作结果暂时无法确认，正在用完全相同的内容核对。请不要重复点击。'
      }
      try {
        const confirmedResult = await action(controller.signal)
        applySuccess(confirmedResult)
      } catch (confirmationError) {
        if (controller.signal.aborted) return
        console.error('核对陪审团操作结果失败:', confirmationError)
        if (isJuryResultUncertain(confirmationError)) {
          await loadQueue({ background: true })
          notice.value = {
            tone: 'warning',
            message: '操作结果仍未确认，已重新读取队列。请先核对页面状态，不要重复点击。'
          }
        } else {
          setFormError(item.reReviewItemId, confirmationError?.message || '操作结果核对失败，请刷新后再试。')
        }
      }
    } else {
      setFormError(item.reReviewItemId, error?.message || '操作失败，请稍后重试。')
    }
  } finally {
    actionControllers.delete(controller)
    setActionActive(key, false)
  }
}

const applyCandidateResult = (item, payload, result) => {
  Object.assign(item, {
    itemStatus: 'voting',
    candidateId: String(result?.candidate_id || ''),
    candidatePayload: payload,
    candidateStatus: 'voting',
    approveCount: 0,
    rejectCount: 0,
    approveWeight: 0,
    rejectWeight: 0,
    reviewOpinions: [],
    myVote: '',
    canSubmitCandidate: false,
    canVote: false,
    isCandidateAuthor: true,
    canAdminReject: false
  })
}

const executeCandidateSubmission = async item => {
  const form = candidateForms.value[item.reReviewItemId]
  if (!form) return
  if (!['existing', 'none'].includes(form.suit_status)) {
    setFormError(item.reReviewItemId, '所属套装必须选择已有套装，或明确选择“无关联套装（纯散件）”。')
    return
  }
  const completePayload = buildJuryCandidatePayload(form, item.basePayload, item.issues)
  const submissionPayload = buildJuryCandidateSubmissionPayload(item, completePayload)
  await runAction({
    key: `candidate:${item.reReviewItemId}`,
    item,
    action: signal => submitJuryCandidate(
      supabase,
      item.reReviewItemId,
      submissionPayload,
      { signal }
    ),
    onSuccess: result => applyCandidateResult(item, completePayload, result),
    successMessage: () => '补充内容已提交，其他用户现在可以参与审核。'
  })
}

const executeVote = async (item, vote) => {
  const reviewNote = item.canSubmitReviewNote
    ? String(reviewNotes.value[item.candidateId] || '').trim()
    : ''
  await runAction({
    key: `vote:${item.candidateId}`,
    item,
    action: signal => castJuryVote(supabase, item.candidateId, vote, reviewNote, { signal }),
    onSuccess: result => {
      const update = buildJuryVoteUpdate(result, vote)
      if (update.approveCount !== null) item.approveCount = update.approveCount
      if (update.rejectCount !== null) item.rejectCount = update.rejectCount
      if (update.approveWeight !== null) item.approveWeight = update.approveWeight
      if (update.rejectWeight !== null) item.rejectWeight = update.rejectWeight
      if (update.status === 'approved') {
        items.value = items.value.filter(current => current.reReviewItemId !== item.reReviewItemId)
      } else if (update.status === 'returned') {
        Object.assign(item, {
          itemStatus: 'pending',
          candidateId: '',
          candidatePayload: null,
          candidateStatus: '',
          candidateSuitName: '',
          approveCount: 0,
          rejectCount: 0,
          approveWeight: 0,
          rejectWeight: 0,
          reviewOpinions: [],
          myVote: '',
          canSubmitCandidate: true,
          canVote: false,
          isCandidateAuthor: false,
          canAdminReject: false
        })
        initializeCandidateForms([item])
      } else {
        item.itemStatus = 'voting'
        item.myVote = update.myVote
        if (update.myReviewNote) {
          item.reviewOpinions = [...item.reviewOpinions, {
            voterLevel: update.myVoterLevel,
            vote: update.myVote,
            reviewNote: update.myReviewNote
          }]
        }
        item.canVote = false
        item.canAdminReject = false
      }
    },
    successMessage: result => Number(result?.points_awarded) === 1
      ? '投票已记录，你获得了 1 积分。'
      : '投票已记录。'
  })
}

const executeAdminReject = async item => {
  const reason = String(adminReasons.value[item.candidateId] || '').trim()
  await runAction({
    key: `admin:${item.candidateId}`,
    item,
    action: signal => rejectJuryCandidateAsAdmin(
      supabase,
      item.candidateId,
      reason,
      { signal }
    ),
    onSuccess: result => {
      if (result?.status === 'rejected') {
        items.value = items.value.filter(current => current.reReviewItemId !== item.reReviewItemId)
      }
    },
    successMessage: result => result?.status === 'awaiting_cosign'
      ? `已完成第 ${result.signature_count} / ${result.required_signatures} 份共签，达到门槛后才会永久驳回。`
      : '管理员终审已记录，该事项已永久驳回。'
  })
}

const askCandidateConfirmation = item => {
  setFormError(item.reReviewItemId)
  confirmation.value = {
    title: '确认提交补充内容',
    message: '提交后，本轮审核期间不能修改。请确认缺失或冲突字段已经核对完成。',
    confirmText: '确认提交',
    tone: 'purple',
    action: () => executeCandidateSubmission(item)
  }
}

const askVoteConfirmation = (item, vote) => {
  const label = vote === JURY_VOTE.APPROVE ? '赞同' : '反对'
  confirmation.value = {
    title: `确认投“${label}”`,
    message: `你正在审核《${item.clothesName}》。投票和复核意见提交后不能修改。`,
    confirmText: `确认${label}`,
    tone: vote === JURY_VOTE.APPROVE ? 'green' : 'rose',
    action: () => executeVote(item, vote)
  }
}

const askAdminConfirmation = item => {
  const reason = String(adminReasons.value[item.candidateId] || '').trim()
  if (!reason) {
    setFormError(item.reReviewItemId, '永久驳回必须填写终审理由。')
    return
  }
  confirmation.value = {
    title: '确认永久驳回',
    message: `该操作与普通投票分开记录，理由为：“${reason}”`,
    confirmText: '永久驳回',
    tone: 'rose',
    action: () => executeAdminReject(item)
  }
}

const confirmPendingAction = () => {
  const action = confirmation.value?.action
  confirmation.value = null
  void action?.()
}

const editableFields = item => getEditableJuryFields(item.issues)
const itemSuitsById = item => {
  const names = new Map(suitsById.value)
  const baseSuitId = String(item.basePayload?.suit_id || '')
  const candidateSuitId = String(item.candidatePayload?.suit_id || '')
  if (baseSuitId && item.baseSuitName) names.set(baseSuitId, { name: item.baseSuitName })
  if (candidateSuitId && item.candidateSuitName) {
    names.set(candidateSuitId, { name: item.candidateSuitName })
  }
  return names
}
const candidateSummary = item => getCandidateSummary(item.candidatePayload, itemSuitsById(item))
const issueValue = (item, issue) => formatJuryFieldValue(
  item.candidatePayload,
  issue.field,
  itemSuitsById(item)
)

watch(() => props.isLoggedIn, () => loadQueue(), { immediate: true })
watch(() => items.value.length, length => {
  activeCardIndex.value = clampJuryCardIndex(activeCardIndex.value, length)
})

onBeforeUnmount(() => {
  queueRequests.invalidate()
  suitRequests.invalidate()
  loadController?.abort()
  suitController?.abort()
  actionControllers.forEach(controller => controller.abort())
  actionControllers.clear()
})
</script>

<template>
  <div class="space-y-5">
    <section class="rounded-2xl border border-purple-100 bg-white p-5 shadow-sm">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 class="text-xl font-black text-slate-800">⚖️ 陪审团</h2>
          <p class="mt-1 text-xs font-bold leading-relaxed text-slate-500">
            每位用户只能提交一次投票；等级决定票权。至少 5 位用户赞同且加权赞同领先时通过；至少 3 位用户反对且加权反对领先 3 票时退回重审。
          </p>
        </div>
        <button
          type="button"
          class="rounded-xl border border-purple-200 px-4 py-2 text-sm font-black text-purple-600 hover:bg-purple-50 disabled:cursor-wait disabled:opacity-50"
          :disabled="isLoading || isRefreshing"
          @click="loadQueue()"
        >
          {{ isLoading || isRefreshing ? '刷新中…' : '刷新陪审团' }}
        </button>
      </div>
    </section>

    <section
      v-if="notice"
      class="rounded-2xl border p-4 text-sm font-bold"
      :class="notice.tone === 'success'
        ? 'border-emerald-100 bg-emerald-50 text-emerald-700'
        : 'border-amber-100 bg-amber-50 text-amber-700'"
    >
      {{ notice.message }}
    </section>

    <section v-if="!isLoggedIn" class="rounded-2xl border border-dashed border-slate-200 bg-white p-8 text-center text-sm font-bold text-slate-400">
      登录后才能查看与你无关的审核事项并参与陪审团。
    </section>

    <section v-else-if="loadError && items.length === 0" class="rounded-2xl border border-rose-100 bg-rose-50 p-6 text-center text-sm font-bold text-rose-600">
      <p>{{ loadError }}</p>
      <button type="button" class="mt-3 underline" @click="loadQueue()">重新加载</button>
    </section>

    <section v-else-if="isLoading && items.length === 0" class="rounded-2xl border border-dashed border-purple-100 bg-white p-8 text-center text-sm font-bold text-purple-500">
      正在读取可参与的审核事项…
    </section>

    <section v-else-if="items.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-white p-8 text-center text-sm font-bold text-slate-400">
      当前没有你可以参与的陪审团事项。
    </section>

    <template v-else>
      <nav class="jury-card-nav" aria-label="陪审事项切换">
        <button
          type="button"
          aria-label="上一条审核事项"
          :disabled="activeCardIndex === 0"
          @click="moveToCard(activeCardIndex - 1)"
        >
          ‹
        </button>
        <span aria-live="polite">{{ activeCardIndex + 1 }} / {{ items.length }}</span>
        <button
          type="button"
          aria-label="下一条审核事项"
          :disabled="activeCardIndex >= items.length - 1"
          @click="moveToCard(activeCardIndex + 1)"
        >
          ›
        </button>
      </nav>
      <div class="jury-card-viewport" @touchstart.passive="handleSwipeStart" @touchend.passive="handleSwipeEnd">
      <article
        v-for="item in activeItem ? [activeItem] : []"
        :key="item.reReviewItemId"
        class="jury-card rounded-2xl border border-slate-100 bg-white p-5 shadow-sm"
      >
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="text-lg font-black text-slate-800">{{ item.clothesName }}</h3>
              <span class="rounded-full bg-purple-50 px-2.5 py-1 text-[11px] font-black text-purple-600">
                {{ getJuryStatusText(item.itemStatus) }}
              </span>
            </div>
            <p class="mt-1 text-xs font-bold text-slate-400">
              {{ item.category || '未知分类' }} · 短编号 {{ item.gameId || '未知' }}
            </p>
          </div>
          <div class="flex gap-2 text-xs font-black">
            <span class="rounded-lg bg-emerald-50 px-3 py-2 text-emerald-600">赞同 {{ item.approveCount }} 人 / {{ item.approveWeight }} 票</span>
            <span class="rounded-lg bg-rose-50 px-3 py-2 text-rose-600">反对 {{ item.rejectCount }} 人 / {{ item.rejectWeight }} 票</span>
          </div>
        </div>

        <div v-if="item.correctionEvidence.length" class="mt-4 rounded-xl border border-sky-100 bg-sky-50 p-4">
          <div class="text-xs font-black text-sky-700">游戏内图鉴图片</div>
          <div class="mt-2 grid gap-3 sm:grid-cols-2">
            <figure v-for="evidence in item.correctionEvidence" :key="evidence.path" class="overflow-hidden rounded-lg bg-white">
              <img
                v-if="evidenceUrls[evidence.path]"
                :src="evidenceUrls[evidence.path]"
                :alt="`${JURY_FIELD_LABELS[evidence.fieldKey] || '资料'}的游戏内图鉴图片`"
                class="block max-h-80 w-full object-contain"
              />
              <figcaption v-else class="p-3 text-xs font-bold text-slate-500">
                {{ evidenceFailures[evidence.path] ? '图片暂时无法读取，请刷新后重试。' : '正在读取图片…' }}
              </figcaption>
            </figure>
          </div>
        </div>

        <div v-if="item.canSubmitCandidate" class="mt-4 rounded-xl border border-purple-100 bg-purple-50/40 p-4">
          <ClothesEntryForm
            v-if="candidateForms[item.reReviewItemId]"
            :form="candidateForms[item.reReviewItemId]"
            :suit-search-text="suitSearchTexts[item.reReviewItemId] || ''"
            :available-suits="suits"
            :visible-fields="editableFields(item)"
            review-mode
            :is-submitting="isActionActive(`candidate:${item.reReviewItemId}`)"
            :allow-pending-review="false"
            :allow-create-suit="false"
            :show-rule-note="false"
            :inline-validation="true"
            submit-text="提交补充内容"
            submit-loading-text="正在提交…"
            @update:suit-search-text="value => (suitSearchTexts[item.reReviewItemId] = value)"
            @validation-error="message => setFormError(item.reReviewItemId, message)"
            @submit="askCandidateConfirmation(item)"
          />
          <p v-if="isSuitsLoading && item.issues.some(issue => issue.field === 'suit')" class="mt-2 text-xs font-bold text-purple-500">
            正在读取套装列表…
          </p>
        </div>

        <div v-else-if="item.candidateId" class="mt-4 rounded-xl border border-slate-100 bg-slate-50 p-4">
          <div class="text-xs font-bold text-slate-400">待审核内容</div>
          <div class="mt-3 grid gap-2 sm:grid-cols-2">
            <div
              v-for="summary in candidateSummary(item)"
              :key="summary.label"
              class="rounded-lg bg-white px-3 py-2"
            >
              <div class="text-[11px] font-bold text-slate-400">{{ summary.label }}</div>
              <div class="mt-0.5 text-sm font-black text-slate-700">{{ summary.value }}</div>
            </div>
          </div>

          <div class="mt-3 space-y-2">
            <div
              v-for="issue in item.issues"
              :key="issue.field"
              class="flex items-center justify-between gap-3 rounded-lg border border-purple-100 bg-purple-50 px-3 py-2 text-sm"
            >
              <span class="font-bold text-purple-600">{{ JURY_FIELD_LABELS[issue.field] || issue.field }}</span>
              <span class="text-right font-black text-slate-700">{{ issueValue(item, issue) }}</span>
            </div>
          </div>

          <p class="mt-3 text-xs font-bold text-slate-500">
            本轮投票期间内容不会变化；如果需要修改，会开启新一轮投票。
          </p>

          <div v-if="item.reviewOpinions.length" class="mt-4 rounded-xl border border-indigo-100 bg-white p-3">
            <div class="text-xs font-black text-indigo-700">匿名复核意见</div>
            <ul class="mt-2 space-y-2">
              <li v-for="(opinion, index) in item.reviewOpinions" :key="`${item.candidateId}-${index}`" class="rounded-lg bg-indigo-50 px-3 py-2 text-xs text-slate-600">
                <strong class="text-indigo-700">Lv{{ opinion.voterLevel }} · {{ opinion.vote === JURY_VOTE.APPROVE ? '赞同' : '反对' }}</strong>
                <p class="mt-1 whitespace-pre-wrap break-words">{{ opinion.reviewNote }}</p>
              </li>
            </ul>
          </div>

          <div v-if="item.myVote" class="mt-4 rounded-lg bg-white px-3 py-2 text-sm font-black text-purple-600">
            你已投：{{ item.myVote === JURY_VOTE.APPROVE ? '赞同' : '反对' }}
          </div>
          <div v-else-if="item.isCandidateAuthor" class="mt-4 rounded-lg bg-white px-3 py-2 text-sm font-black text-slate-500">
            这是你补充的内容，不能参与本轮投票。
          </div>
          <div v-else class="mt-4 space-y-3">
            <label v-if="item.canSubmitReviewNote" class="block rounded-xl border border-indigo-100 bg-white p-3">
              <span class="text-xs font-black text-indigo-700">复核意见（选填，提交后不可修改）</span>
              <textarea
                v-model="reviewNotes[item.candidateId]"
                maxlength="200"
                rows="3"
                class="mt-2 w-full resize-y rounded-lg border border-slate-200 px-3 py-2 text-sm text-slate-700 outline-none focus:border-indigo-400"
                placeholder="写明判断依据，不要填写个人联系方式或其他隐私信息"
              ></textarea>
              <small class="mt-1 block text-right text-[10px] font-bold text-slate-400">{{ String(reviewNotes[item.candidateId] || '').length }} / 200</small>
            </label>
            <p v-else class="rounded-lg bg-white px-3 py-2 text-xs font-bold text-slate-500">
              当前 Lv{{ item.currentUserLevel }}，达到 Lv2 后可在投票时附匿名复核意见。
            </p>
            <div class="grid grid-cols-2 gap-3">
            <button
              type="button"
              class="rounded-xl bg-emerald-500 px-4 py-3 text-sm font-black text-white disabled:opacity-50"
              :disabled="!item.canVote || isItemBusy(item)"
              @click="askVoteConfirmation(item, JURY_VOTE.APPROVE)"
            >
              确认正确
            </button>
            <button
              type="button"
              class="rounded-xl bg-rose-500 px-4 py-3 text-sm font-black text-white disabled:opacity-50"
              :disabled="!item.canVote || isItemBusy(item)"
              @click="askVoteConfirmation(item, JURY_VOTE.REJECT)"
            >
              需要修改
            </button>
            </div>
          </div>

          <div v-if="canPermanentlyReject" class="mt-5 border-t border-slate-200 pt-4">
            <div class="text-xs font-black text-rose-600">{{ isSuperAdmin ? '站长独立终审' : '普通管理员多人共签终审' }}</div>
            <p v-if="!isSuperAdmin" class="mt-2 rounded-lg bg-rose-50 px-3 py-2 text-xs font-bold text-rose-700">永久驳回需要 2 位不同的当前有效普通管理员对同一理由共签。</p>
            <p v-if="!item.canAdminReject" class="mt-2 rounded-lg bg-white px-3 py-2 text-xs font-bold text-slate-500">
              你已参与普通投票、提交过本次内容或参与过原始录入，因此不能再执行终审。
            </p>
            <div v-else class="mt-2 flex flex-col gap-2 sm:flex-row">
              <input
                v-model="adminReasons[item.candidateId]"
                type="text"
                maxlength="200"
                placeholder="填写永久驳回理由"
                class="min-w-0 flex-1 rounded-xl border border-rose-200 bg-white px-3 py-2 text-sm font-bold text-slate-700"
              />
              <button
                type="button"
                class="rounded-xl border border-rose-200 bg-white px-4 py-2 text-sm font-black text-rose-600 disabled:opacity-50"
                :disabled="isItemBusy(item)"
                @click="askAdminConfirmation(item)"
              >
                永久驳回
              </button>
            </div>
          </div>
        </div>

        <p v-if="formErrors[item.reReviewItemId]" class="mt-3 rounded-lg bg-rose-50 px-3 py-2 text-sm font-bold text-rose-600">
          {{ formErrors[item.reReviewItemId] }}
        </p>
      </article>
      </div>
    </template>

    <Teleport to="body">
      <div v-if="confirmation" class="fixed inset-0 z-[100] flex items-center justify-center bg-slate-900/40 p-4" @click.self="confirmation = null">
        <div class="w-full max-w-md rounded-2xl bg-white p-5 shadow-2xl">
          <h3 class="text-lg font-black text-slate-800">{{ confirmation.title }}</h3>
          <p class="mt-2 text-sm font-bold leading-relaxed text-slate-600">{{ confirmation.message }}</p>
          <div class="mt-5 flex justify-end gap-3">
            <button type="button" class="rounded-xl border border-slate-200 px-4 py-2 text-sm font-black text-slate-500" @click="confirmation = null">
              取消
            </button>
            <button
              type="button"
              class="rounded-xl px-4 py-2 text-sm font-black text-white"
              :class="confirmation.tone === 'green' ? 'bg-emerald-500' : confirmation.tone === 'rose' ? 'bg-rose-500' : 'bg-purple-500'"
              @click="confirmPendingAction"
            >
              {{ confirmation.confirmText }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.jury-card-nav {
  display: grid;
  grid-template-columns: 44px 1fr 44px;
  align-items: center;
  gap: 10px;
  margin-bottom: 10px;
}
.jury-card-nav span {
  color: #7c3aed;
  font-size: 12px;
  font-weight: 900;
  text-align: center;
}
.jury-card-nav button {
  height: 40px;
  border: 1px solid #e9d5ff;
  border-radius: 12px;
  background: #fff;
  color: #7c3aed;
  font-size: 25px;
  font-weight: 900;
  line-height: 1;
}
.jury-card-nav button:disabled { opacity: 0.35; }
.jury-card-viewport { min-width: 0; touch-action: pan-y; }
.jury-card { min-width: 0; }

@media (max-width: 640px) {
  .jury-card {
    max-height: calc(100dvh - 11.5rem);
    overflow-y: auto;
    overscroll-behavior: contain;
    padding: 16px;
  }
  .jury-card-nav {
    position: sticky;
    top: 8px;
    z-index: 20;
    margin-inline: 8px;
    padding: 6px;
    border: 1px solid #f3e8ff;
    border-radius: 14px;
    background: rgba(255, 255, 255, 0.94);
    backdrop-filter: blur(10px);
  }
}
</style>
