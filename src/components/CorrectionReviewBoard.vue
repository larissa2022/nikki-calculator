<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { supabase } from '../api/supabase'
import {
  createCorrectionRequestGate,
  fetchCorrectionReviewQueue,
  isCorrectionResultUncertain,
  reviewCorrectionRequest
} from '../api/correctionService'
import {
  buildCorrectionAcceptedValue,
  createCorrectionReviewDraft,
  formatCorrectionReviewValue,
  getCorrectionFieldLabel,
  validateCorrectionReview
} from '../utils/correctionRules'
import { ATTRIBUTE_PAIRS, FULL_CATEGORIES } from '../utils/gameConstants'

const props = defineProps({
  suitList: { type: Array, default: () => [] }
})

const items = ref([])
const drafts = ref({})
const isLoading = ref(false)
const isRefreshing = ref(false)
const loadError = ref('')
const notice = ref(null)
const confirmation = ref(null)
const activeRequestId = ref('')
const formErrors = ref({})
const requestGate = createCorrectionRequestGate()
let loadController
const actionControllers = new Set()

const suitsById = computed(() => new Map(
  props.suitList.map(suit => [String(suit.id), suit])
))

const initializeDrafts = rows => {
  const next = { ...drafts.value }
  rows.forEach(item => {
    if (!next[item.requestId]) next[item.requestId] = createCorrectionReviewDraft(item)
  })
  drafts.value = next
}

const loadQueue = async ({ background = false } = {}) => {
  const requestId = requestGate.next()
  loadController?.abort()
  const controller = new AbortController()
  loadController = controller
  const hasExistingItems = items.value.length > 0
  isLoading.value = !background && !hasExistingItems
  isRefreshing.value = background || hasExistingItems
  loadError.value = ''

  try {
    const rows = await fetchCorrectionReviewQueue(supabase, { signal: controller.signal })
    if (!requestGate.isCurrent(requestId)) return
    items.value = rows
    initializeDrafts(rows)
  } catch (error) {
    if (controller.signal.aborted || !requestGate.isCurrent(requestId)) return
    console.error('加载图鉴报错处理队列失败:', error)
    if (hasExistingItems) {
      notice.value = { tone: 'warning', message: `刷新失败，已保留当前内容：${error?.message || '请稍后重试。'}` }
    } else {
      loadError.value = error?.message || '图鉴报错处理队列暂时无法加载。'
    }
  } finally {
    if (requestGate.isCurrent(requestId)) {
      isLoading.value = false
      isRefreshing.value = false
    }
  }
}

const proposalText = item => {
  const value = item.proposedPatch?.[item.fieldKey]
  if (value && typeof value === 'object') return JSON.stringify(value)
  return value === null || value === undefined || value === '' ? '未填写明确建议' : String(value)
}

const currentText = item => formatCorrectionReviewValue(
  item.currentValue,
  item.fieldKey,
  suitsById.value
)

const setFormError = (requestId, message = '') => {
  formErrors.value = { ...formErrors.value, [requestId]: message }
}

const applyReviewSuccess = (item, action, result) => {
  items.value = items.value.filter(current => current.requestId !== item.requestId)
  const actionText = action === 'approve_empty'
    ? '已补全正式图鉴'
    : action === 'send_to_jury'
      ? '已转交陪审团'
      : '已记录不采纳'
  const pointsText = Number(result?.points_awarded) === 5 ? '，报错用户获得 5 积分' : ''
  notice.value = { tone: 'success', message: `${actionText}${pointsText}。` }
  void loadQueue({ background: true })
}

const executeReview = async (item, action) => {
  if (activeRequestId.value) return
  const draft = drafts.value[item.requestId]
  const controller = new AbortController()
  actionControllers.add(controller)
  activeRequestId.value = item.requestId
  setFormError(item.requestId)
  const payload = {
    requestId: item.requestId,
    action,
    acceptedValue: action === 'reject'
      ? null
      : buildCorrectionAcceptedValue(item.fieldKey, draft),
    resolutionNote: String(draft.resolutionNote || '').trim()
  }

  try {
    const result = await reviewCorrectionRequest(supabase, payload, { signal: controller.signal })
    applyReviewSuccess(item, action, result)
  } catch (error) {
    if (controller.signal.aborted) return
    console.error('处理图鉴报错失败:', error)
    if (isCorrectionResultUncertain(error)) {
      notice.value = {
        tone: 'warning',
        message: '处理结果暂时无法确认，正在用相同内容核对。请不要重复点击。'
      }
      try {
        const confirmedResult = await reviewCorrectionRequest(supabase, payload, { signal: controller.signal })
        applyReviewSuccess(item, action, confirmedResult)
      } catch (confirmationError) {
        if (controller.signal.aborted) return
        console.error('核对图鉴报错处理结果失败:', confirmationError)
        if (isCorrectionResultUncertain(confirmationError)) {
          await loadQueue({ background: true })
          notice.value = {
            tone: 'warning',
            message: '处理结果仍未确认，已重新读取队列。请先核对页面状态，不要重复点击。'
          }
        } else {
          setFormError(item.requestId, confirmationError?.message || '处理结果核对失败，请刷新后再试。')
        }
      }
    } else {
      setFormError(item.requestId, error?.message || '处理失败，请稍后重试。')
    }
  } finally {
    actionControllers.delete(controller)
    if (activeRequestId.value === item.requestId) activeRequestId.value = ''
  }
}

const askReviewConfirmation = (item, action) => {
  const draft = drafts.value[item.requestId]
  const error = validateCorrectionReview(item.fieldKey, draft, action)
  setFormError(item.requestId, error)
  if (error) return

  const config = action === 'approve_empty'
    ? {
        title: '确认补全正式图鉴',
        message: '该字段当前缺失，确认后会立即写入核对结果，并给报错用户发放 5 积分。',
        confirmText: '确认补全',
        tone: 'green'
      }
    : action === 'send_to_jury'
      ? {
          title: '确认转交陪审团',
          message: '正式图鉴当前已有内容。确认后会创建或复用该服装的全字段审核事项，只有最终采用这份核对结果时才奖励报错用户。',
          confirmText: '转交陪审',
          tone: 'purple'
        }
      : {
          title: '确认不采纳',
          message: '这条报错将结案，不会修改正式图鉴，也不会发放积分。',
          confirmText: '不采纳',
          tone: 'rose'
        }

  confirmation.value = { ...config, action: () => executeReview(item, action) }
}

const confirmPendingAction = () => {
  const action = confirmation.value?.action
  confirmation.value = null
  void action?.()
}

onMounted(() => loadQueue())

onBeforeUnmount(() => {
  requestGate.invalidate()
  loadController?.abort()
  actionControllers.forEach(controller => controller.abort())
  actionControllers.clear()
})
</script>

<template>
  <div class="space-y-5">
    <section class="rounded-2xl border border-orange-100 bg-white p-5 shadow-sm">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 class="text-xl font-black text-slate-800">📝 图鉴报错处理</h2>
          <p class="mt-1 text-xs font-bold leading-relaxed text-slate-500">
            空字段核实后可直接补全；已有内容的争议修正必须交给陪审团。管理员不能处理自己提交的报错。
          </p>
        </div>
        <button
          type="button"
          class="rounded-xl border border-orange-200 px-4 py-2 text-sm font-black text-orange-600 hover:bg-orange-50 disabled:cursor-wait disabled:opacity-50"
          :disabled="isLoading || isRefreshing"
          @click="loadQueue()"
        >
          {{ isLoading || isRefreshing ? '刷新中…' : '刷新报错队列' }}
        </button>
      </div>
    </section>

    <section
      v-if="notice"
      class="rounded-2xl border p-4 text-sm font-bold"
      :class="notice.tone === 'success' ? 'border-emerald-100 bg-emerald-50 text-emerald-700' : 'border-amber-100 bg-amber-50 text-amber-700'"
    >
      {{ notice.message }}
    </section>

    <section v-if="loadError && items.length === 0" class="rounded-2xl border border-rose-100 bg-rose-50 p-6 text-center text-sm font-bold text-rose-600">
      <p>{{ loadError }}</p>
      <button type="button" class="mt-3 underline" @click="loadQueue()">重新加载</button>
    </section>

    <section v-else-if="isLoading && items.length === 0" class="rounded-2xl border border-dashed border-orange-100 bg-white p-8 text-center text-sm font-bold text-orange-500">
      正在读取待处理报错…
    </section>

    <section v-else-if="items.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-white p-8 text-center text-sm font-bold text-slate-400">
      当前没有待处理的图鉴报错。
    </section>

    <article v-for="item in items" :key="item.requestId" class="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-lg font-black text-slate-800">{{ item.clothesName }}</h3>
            <span class="rounded-full bg-orange-50 px-2.5 py-1 text-[11px] font-black text-orange-600">
              {{ getCorrectionFieldLabel(item.fieldKey) }}
            </span>
          </div>
          <p class="mt-1 text-xs font-bold text-slate-400">
            {{ item.category || '未知分类' }} · 短编号 {{ item.gameId || '未知' }} · {{ item.reporterName }}
          </p>
        </div>
        <span class="rounded-lg px-3 py-2 text-xs font-black" :class="item.isOwnRequest ? 'bg-rose-50 text-rose-600' : item.canApproveDirectly ? 'bg-emerald-50 text-emerald-600' : item.canSendToJury ? 'bg-purple-50 text-purple-600' : 'bg-slate-100 text-slate-500'">
          {{ item.isOwnRequest ? '不能处理本人报错' : item.canApproveDirectly ? '可直接补全' : item.canSendToJury ? '需要陪审' : '仅可不采纳' }}
        </span>
      </div>

      <div class="mt-4 grid gap-3 sm:grid-cols-2">
        <div class="rounded-xl border border-slate-100 bg-slate-50 p-3">
          <div class="text-[11px] font-black text-slate-400">正式图鉴当前内容</div>
          <div class="mt-1 break-words text-sm font-black text-slate-700">{{ currentText(item) }}</div>
        </div>
        <div class="rounded-xl border border-orange-100 bg-orange-50 p-3">
          <div class="text-[11px] font-black text-orange-500">用户建议</div>
          <div class="mt-1 break-words text-sm font-black text-orange-800">{{ proposalText(item) }}</div>
        </div>
      </div>
      <div class="mt-3 rounded-xl border border-slate-100 px-3 py-3 text-sm font-bold leading-relaxed text-slate-600">
        {{ item.reason }}
      </div>

      <div v-if="item.canReview && item.fieldKey !== 'other'" class="mt-4 rounded-xl border border-purple-100 bg-purple-50/40 p-4">
        <div class="mb-3 text-xs font-black text-purple-600">管理员核对结果</div>
        <input
          v-if="['name', 'game_id', 'tags'].includes(item.fieldKey)"
          v-model="drafts[item.requestId].value"
          type="text"
          :maxlength="item.fieldKey === 'tags' ? 500 : 200"
          class="w-full rounded-xl border border-purple-100 bg-white px-3 py-2 text-sm font-bold text-slate-700"
          :placeholder="item.fieldKey === 'tags' ? '留空表示无特殊标签' : '填写核对后的内容'"
        />
        <select
          v-else-if="item.fieldKey === 'category'"
          v-model="drafts[item.requestId].value"
          class="w-full rounded-xl border border-purple-100 bg-white px-3 py-2 text-sm font-bold text-slate-700"
        >
          <option value="">请选择分类部位</option>
          <option v-for="category in FULL_CATEGORIES" :key="category" :value="category">{{ category }}</option>
        </select>
        <select
          v-else-if="item.fieldKey === 'stars'"
          v-model.number="drafts[item.requestId].stars"
          class="w-full rounded-xl border border-purple-100 bg-white px-3 py-2 text-sm font-bold text-slate-700"
        >
          <option v-for="stars in 6" :key="stars" :value="stars">{{ stars }} 星</option>
        </select>
        <div v-else-if="item.fieldKey === 'scores'" class="space-y-2">
          <div v-for="pair in ATTRIBUTE_PAIRS" :key="pair.key" class="grid grid-cols-2 gap-2">
            <label v-for="option in pair.options" :key="option.value" class="rounded-lg bg-white p-2 text-xs font-black text-slate-500">
              {{ option.label }}
              <input v-model.number="drafts[item.requestId].scores[option.value]" type="number" min="0" step="1" class="mt-1 w-full rounded-lg border border-purple-100 px-2 py-1.5 text-sm text-slate-700" />
            </label>
          </div>
        </div>
        <div v-else-if="item.fieldKey === 'suit'" class="space-y-3">
          <label class="flex items-center gap-2 text-sm font-black text-slate-600">
            <input v-model="drafts[item.requestId].noSuit" type="checkbox" />
            核对为无关联套装（纯散件）
          </label>
          <select v-model="drafts[item.requestId].suitId" :disabled="drafts[item.requestId].noSuit" class="w-full rounded-xl border border-purple-100 bg-white px-3 py-2 text-sm font-bold text-slate-700 disabled:opacity-50">
            <option value="">请选择已有套装</option>
            <option v-for="suit in suitList" :key="suit.id" :value="String(suit.id)">《{{ suit.name }}》</option>
          </select>
        </div>
      </div>

      <div v-if="item.isOwnRequest" class="mt-4 rounded-xl border border-rose-100 bg-rose-50 p-4 text-sm font-bold text-rose-700">
        这是你本人提交的报错。为避免自审，你不能填写处理结果或执行任何结案操作，请交由其他管理员处理。
      </div>

      <label v-if="item.canReview" class="mt-4 block text-xs font-black text-slate-500">
        处理说明（10—1000 字）
        <textarea v-model="drafts[item.requestId].resolutionNote" maxlength="1000" rows="3" class="mt-2 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700" placeholder="说明核对依据，以及直接补全、转交陪审或不采纳的原因。"></textarea>
      </label>

      <p v-if="formErrors[item.requestId]" class="mt-3 rounded-lg bg-rose-50 px-3 py-2 text-sm font-bold text-rose-600">
        {{ formErrors[item.requestId] }}
      </p>

      <div v-if="item.canReview" class="mt-4 flex flex-col gap-2 sm:flex-row sm:justify-end">
        <button type="button" class="rounded-xl border border-slate-200 px-4 py-2 text-sm font-black text-slate-500 disabled:opacity-50" :disabled="Boolean(activeRequestId)" @click="askReviewConfirmation(item, 'reject')">
          不采纳
        </button>
        <button v-if="item.canSendToJury" type="button" class="rounded-xl bg-purple-500 px-4 py-2 text-sm font-black text-white disabled:opacity-50" :disabled="Boolean(activeRequestId)" @click="askReviewConfirmation(item, 'send_to_jury')">
          转交陪审团
        </button>
        <button v-if="item.canApproveDirectly" type="button" class="rounded-xl bg-emerald-500 px-4 py-2 text-sm font-black text-white disabled:opacity-50" :disabled="Boolean(activeRequestId)" @click="askReviewConfirmation(item, 'approve_empty')">
          补全正式图鉴
        </button>
      </div>
    </article>

    <div v-if="confirmation" class="fixed inset-0 z-[100] flex items-center justify-center bg-slate-900/40 p-4" @click.self="confirmation = null">
      <div class="w-full max-w-md rounded-2xl bg-white p-5 shadow-2xl">
        <h3 class="text-lg font-black text-slate-800">{{ confirmation.title }}</h3>
        <p class="mt-2 text-sm font-bold leading-relaxed text-slate-600">{{ confirmation.message }}</p>
        <div class="mt-5 flex justify-end gap-3">
          <button type="button" class="rounded-xl border border-slate-200 px-4 py-2 text-sm font-black text-slate-500" @click="confirmation = null">取消</button>
          <button type="button" class="rounded-xl px-4 py-2 text-sm font-black text-white" :class="confirmation.tone === 'green' ? 'bg-emerald-500' : confirmation.tone === 'rose' ? 'bg-rose-500' : 'bg-purple-500'" @click="confirmPendingAction">
            {{ confirmation.confirmText }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
