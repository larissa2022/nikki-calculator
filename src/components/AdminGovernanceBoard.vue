<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import {
  createAdminCandidateExclusion,
  createManualAdminTerm,
  endAdminTerm,
  fetchAdminGovernance,
  revokeAdminCandidateExclusion
} from '../api/adminCapabilitiesService'
import {
  CANDIDATE_EXCLUSION_STATUS,
  groupCandidateExclusions
} from '../utils/adminGovernance'

const props = defineProps({ allowTermManagement: Boolean })
const data = ref({ users: [], terms: [], exclusions: [], candidates: [], decisions: [], communityActions: [] })
const isLoading = ref(false)
const errorMessage = ref('')
const activeSection = ref(props.allowTermManagement ? 'terms' : 'exclusions')
const manualForm = reactive({ userId: '', reason: '', endsAt: '' })
const exclusionForm = reactive({ userId: '', reason: '', startsAt: '', endsAt: '' })
const actionNotice = ref('')

const activeTerms = computed(() => data.value.terms.filter(term => term.status === 'active' && new Date(term.scheduled_end_at) > new Date()))
const availableUsers = computed(() => data.value.users)
const groupedExclusions = computed(() => groupCandidateExclusions(data.value.exclusions))
const currentExclusions = computed(() => groupedExclusions.value.current)
const exclusionHistory = computed(() => groupedExclusions.value.history)
const visibleSections = computed(() => [
  ...(props.allowTermManagement ? [{ key: 'terms', label: '任期' }] : []),
  { key: 'exclusions', label: '候选限制' },
  { key: 'candidates', label: '候选名单' },
  { key: 'decisions', label: '审核记录' },
  { key: 'actions', label: '确认记录' }
])

const formatTime = (value) => value ? new Date(value).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }) : '—'
const sourceLabel = (source) => ({ monthly: '月度轮值', manual: '手动任期', legacy_transition: '旧管理员过渡' }[source] || source)
const exclusionStatusLabel = (status) => ({
  [CANDIDATE_EXCLUSION_STATUS.ACTIVE]: '生效中',
  [CANDIDATE_EXCLUSION_STATUS.SCHEDULED]: '待生效',
  [CANDIDATE_EXCLUSION_STATUS.EXPIRED]: '已过期',
  [CANDIDATE_EXCLUSION_STATUS.REVOKED]: '已撤销',
  [CANDIDATE_EXCLUSION_STATUS.INVALID]: '时间异常'
}[status] || '状态未知')
const exclusionStatusClass = (status) => ({
  [CANDIDATE_EXCLUSION_STATUS.ACTIVE]: 'bg-emerald-50 text-emerald-700',
  [CANDIDATE_EXCLUSION_STATUS.SCHEDULED]: 'bg-sky-50 text-sky-700',
  [CANDIDATE_EXCLUSION_STATUS.EXPIRED]: 'bg-slate-100 text-slate-600',
  [CANDIDATE_EXCLUSION_STATUS.REVOKED]: 'bg-amber-50 text-amber-700',
  [CANDIDATE_EXCLUSION_STATUS.INVALID]: 'bg-rose-50 text-rose-700'
}[status] || 'bg-slate-100 text-slate-600')
const actionTypeLabel = (type) => ({
  suit_approve: '套装通过',
  suit_reject: '套装驳回',
  jury_permanent_reject: '永久驳回',
  jury_reopen: '永久驳回纠错',
  manual_term_create: '创建手动任期',
  term_end: '提前结束任期',
  candidate_exclusion_create: '新增候选排除',
  candidate_exclusion_revoke: '撤销候选排除'
}[type] || type)
const actionStatusLabel = (status) => ({ proposed: '等待其他管理员确认', executed: '已执行', superseded: '已被其他决定取代', cancelled: '已失效' }[status] || status)
const resultNotice = (result, executedMessage) => result?.status === 'awaiting_cosign'
  ? `你的确认已记录（${result.signature_count} / ${result.required_signatures}）。还需要其他管理员确认。`
  : executedMessage

const load = async () => {
  isLoading.value = true
  errorMessage.value = ''
  try {
    data.value = await fetchAdminGovernance()
  } catch (error) {
    errorMessage.value = error.message || '管理记录读取失败'
  } finally {
    isLoading.value = false
  }
}

const submitManual = async () => {
  if (!manualForm.userId.trim() || !manualForm.reason.trim() || !manualForm.endsAt) return window.alert('请完整填写用户 UUID、原因和结束时间。')
  try {
    const result = await createManualAdminTerm({
      userId: manualForm.userId.trim(),
      reason: manualForm.reason.trim(),
      endsAt: new Date(manualForm.endsAt).toISOString()
    })
    Object.assign(manualForm, { userId: '', reason: '', endsAt: '' })
    await load()
    actionNotice.value = resultNotice(result, '手动任期已创建。')
  } catch (error) {
    window.alert(error.message || '手动任期创建失败')
  }
}

const stopTerm = async (term) => {
  const reason = window.prompt(`请填写提前结束「${term.display_name}」任期的原因：`)?.trim()
  if (!reason) return
  try {
    const result = await endAdminTerm(term.id, reason)
    await load()
    actionNotice.value = resultNotice(result, '目标任期已提前结束。')
  } catch (error) {
    window.alert(error.message || '任期结束失败')
  }
}

const submitExclusion = async () => {
  if (!exclusionForm.userId.trim() || !exclusionForm.reason.trim() || !exclusionForm.startsAt || !exclusionForm.endsAt) return window.alert('请完整填写候选排除信息。')
  const startsAt = new Date(exclusionForm.startsAt)
  const endsAt = new Date(exclusionForm.endsAt)
  if (!Number.isFinite(startsAt.getTime()) || !Number.isFinite(endsAt.getTime()) || endsAt <= startsAt) return window.alert('排除结束时间必须晚于开始时间。')
  if (endsAt <= new Date()) return window.alert('排除结束时间必须晚于当前时间。')
  try {
    const result = await createAdminCandidateExclusion({
      userId: exclusionForm.userId.trim(),
      reason: exclusionForm.reason.trim(),
      startsAt: startsAt.toISOString(),
      endsAt: endsAt.toISOString()
    })
    Object.assign(exclusionForm, { userId: '', reason: '', startsAt: '', endsAt: '' })
    await load()
    actionNotice.value = resultNotice(result, '候选排除已创建，可在下方“当前及待生效排除”中撤销。')
  } catch (error) {
    window.alert(error.message || '候选排除创建失败')
  }
}

const revokeExclusion = async (item) => {
  const reason = window.prompt(`请填写撤销「${item.display_name}」候选排除的原因。`)?.trim()
  if (!reason) return
  try {
    const result = await revokeAdminCandidateExclusion(item.id, reason)
    await load()
    actionNotice.value = resultNotice(result, '候选排除已撤销，记录已保留在历史中。')
  } catch (error) {
    window.alert(error.message || '候选排除撤销失败')
  }
}

onMounted(load)
</script>

<template>
  <section class="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm md:p-6">
    <div class="mb-5 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h3 class="text-xl font-black text-slate-800">🛡️ {{ allowTermManagement ? '任期与候选管理' : '候选管理' }}</h3>
        <p class="mt-1 text-xs font-bold text-slate-500">{{ allowTermManagement ? '站长可以管理手动任期和候选限制。' : '候选限制需要三位管理员确认。手动任期只由站长管理。' }}</p>
      </div>
      <button class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-black text-slate-600" @click="load">刷新</button>
    </div>

    <div class="mb-5 flex flex-wrap gap-2">
      <button v-for="item in visibleSections" :key="item.key" class="rounded-full px-4 py-2 text-xs font-black" :class="activeSection === item.key ? 'bg-purple-600 text-white' : 'bg-slate-100 text-slate-600'" @click="activeSection = item.key">{{ item.label }}</button>
    </div>

    <p v-if="actionNotice" class="mb-4 rounded-xl bg-emerald-50 p-3 text-sm font-bold text-emerald-700">{{ actionNotice }}</p>

    <p v-if="isLoading" class="py-8 text-center font-bold text-slate-400">读取中…</p>
    <p v-else-if="errorMessage" class="rounded-xl bg-rose-50 p-4 font-bold text-rose-700">{{ errorMessage }}</p>

    <template v-else-if="activeSection === 'terms'">
      <form class="mb-5 grid grid-cols-1 gap-3 rounded-xl bg-slate-50 p-4 md:grid-cols-2" @submit.prevent="submitManual">
        <select v-model="manualForm.userId" class="rounded-lg border border-slate-200 px-3 py-2 text-sm">
          <option value="">选择用户</option>
          <option v-for="user in availableUsers" :key="user.id" :value="user.id">{{ user.display_name }}</option>
        </select>
        <input v-model="manualForm.endsAt" type="datetime-local" class="rounded-lg border border-slate-200 px-3 py-2 text-sm" />
        <input v-model="manualForm.reason" class="rounded-lg border border-slate-200 px-3 py-2 text-sm md:col-span-2" placeholder="手动授予原因（必填）" />
        <button class="rounded-lg bg-purple-600 px-4 py-2 text-sm font-black text-white md:col-span-2">创建手动任期</button>
      </form>
      <div class="space-y-3">
        <article v-for="term in activeTerms" :key="term.id" class="flex flex-col justify-between gap-3 rounded-xl border border-slate-100 p-4 md:flex-row md:items-center">
          <div><div class="font-black text-slate-800">{{ term.display_name }} · {{ sourceLabel(term.source) }}</div><div class="mt-1 text-xs font-bold text-slate-500">至 {{ formatTime(term.scheduled_end_at) }}<span v-if="term.reason"> · {{ term.reason }}</span></div></div>
          <button class="rounded-lg border border-rose-200 px-3 py-2 text-xs font-black text-rose-600" @click="stopTerm(term)">提前结束</button>
        </article>
        <p v-if="activeTerms.length === 0" class="py-5 text-center font-bold text-slate-400">暂无有效普通管理员任期。</p>
      </div>
    </template>

    <template v-else-if="activeSection === 'exclusions'">
      <form class="mb-5 grid grid-cols-1 gap-3 rounded-xl bg-slate-50 p-4 md:grid-cols-2" @submit.prevent="submitExclusion">
        <select v-model="exclusionForm.userId" class="rounded-lg border border-slate-200 px-3 py-2 text-sm md:col-span-2">
          <option value="">选择用户</option>
          <option v-for="user in availableUsers" :key="user.id" :value="user.id">{{ user.display_name }}</option>
        </select>
        <label class="text-xs font-black text-slate-600">开始时间<input v-model="exclusionForm.startsAt" type="datetime-local" class="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm font-normal" /></label>
        <label class="text-xs font-black text-slate-600">结束时间<input v-model="exclusionForm.endsAt" type="datetime-local" class="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm font-normal" /></label>
        <input v-model="exclusionForm.reason" class="rounded-lg border border-slate-200 px-3 py-2 text-sm md:col-span-2" placeholder="限制原因（必填）" />
        <button class="rounded-lg bg-purple-600 px-4 py-2 text-sm font-black text-white md:col-span-2">提交候选限制</button>
      </form>
      <div class="mb-6">
        <h4 class="mb-3 text-sm font-black text-slate-700">当前及待生效限制（{{ currentExclusions.length }}）</h4>
        <div class="space-y-3">
          <article v-for="item in currentExclusions" :key="item.id" class="flex flex-col justify-between gap-3 rounded-xl border border-slate-100 p-4 md:flex-row md:items-center">
            <div>
              <div class="flex flex-wrap items-center gap-2"><span class="font-black text-slate-800">{{ item.display_name }}</span><span class="rounded-full px-2 py-1 text-[11px] font-black" :class="exclusionStatusClass(item.view_status)">{{ exclusionStatusLabel(item.view_status) }}</span></div>
              <div class="mt-1 text-xs font-bold text-slate-500">{{ item.reason }} · {{ formatTime(item.starts_at) }} 至 {{ formatTime(item.ends_at) }}</div>
            </div>
            <button class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-black text-slate-600" @click="revokeExclusion(item)">撤销排除</button>
          </article>
          <p v-if="currentExclusions.length === 0" class="rounded-xl bg-slate-50 py-5 text-center text-sm font-bold text-slate-400">暂无可撤销的候选限制。</p>
        </div>
      </div>

      <div>
        <h4 class="mb-3 text-sm font-black text-slate-700">限制历史（{{ exclusionHistory.length }}）</h4>
        <div class="space-y-3">
          <article v-for="item in exclusionHistory" :key="item.id" class="rounded-xl border border-slate-100 p-4">
            <div class="flex flex-wrap items-center gap-2"><span class="font-black text-slate-700">{{ item.display_name }}</span><span class="rounded-full px-2 py-1 text-[11px] font-black" :class="exclusionStatusClass(item.view_status)">{{ exclusionStatusLabel(item.view_status) }}</span></div>
            <div class="mt-1 text-xs font-bold text-slate-500">{{ item.reason }} · {{ formatTime(item.starts_at) }} 至 {{ formatTime(item.ends_at) }}</div>
          </article>
          <p v-if="exclusionHistory.length === 0" class="rounded-xl bg-slate-50 py-5 text-center text-sm font-bold text-slate-400">暂无已过期或已撤销记录。</p>
        </div>
      </div>
    </template>

    <div v-else-if="activeSection === 'candidates'" class="overflow-x-auto">
      <table class="w-full text-left text-xs"><thead><tr class="border-b text-slate-400"><th class="p-2">服务月/顺序</th><th class="p-2">用户</th><th class="p-2">等级/积分/行为</th><th class="p-2">结果</th></tr></thead><tbody><tr v-for="item in data.candidates" :key="`${item.service_month}-${item.candidate_order}`" class="border-b border-slate-50"><td class="p-2 font-bold">{{ item.service_month }} · #{{ item.candidate_order }}</td><td class="p-2">{{ item.display_name }}</td><td class="p-2">Lv{{ item.level_at_snapshot ?? '-' }} · {{ item.frozen_points }} / {{ item.qualifying_action_count }}</td><td class="p-2">{{ item.skip_reason || '符合条件' }}</td></tr></tbody></table>
    </div>

    <div v-else-if="activeSection === 'decisions'" class="space-y-3">
      <article v-for="item in data.decisions" :key="item.id" class="rounded-xl border border-slate-100 p-4 text-sm"><div class="font-black" :class="item.action === 'approved' ? 'text-emerald-700' : 'text-rose-700'">{{ item.action === 'approved' ? '通过' : '驳回' }} · {{ item.adopted_payload?.name || '未命名服装' }}</div><div class="mt-1 text-xs font-bold text-slate-500">审核者 {{ item.reviewer_display_name }}<span v-if="item.term_source"> · {{ sourceLabel(item.term_source) }}至 {{ formatTime(item.term_ends_at) }}</span> · 采用 {{ item.adopted_count }} / 全部来源 {{ item.source_count }} · {{ formatTime(item.created_at) }}<span v-if="item.reason"> · {{ item.reason }}</span></div></article>
    </div>

    <div v-else class="space-y-3">
      <article v-for="item in data.communityActions" :key="item.id" class="rounded-xl border border-slate-100 p-4 text-sm">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="font-black text-slate-800">{{ actionTypeLabel(item.action_type) }} · {{ actionStatusLabel(item.status) }}</div>
          <div class="rounded-full bg-purple-50 px-3 py-1 text-xs font-black text-purple-700">{{ item.valid_signature_count }} / {{ item.required_signatures }}</div>
        </div>
        <div class="mt-1 text-xs font-bold text-slate-500">{{ item.reason }} · {{ formatTime(item.created_at) }}</div>
        <div v-if="item.signatures?.length" class="mt-2 text-xs font-bold text-slate-500">已确认：{{ item.signatures.map(signature => signature.display_name).join('、') }}</div>
      </article>
      <p v-if="data.communityActions.length === 0" class="rounded-xl bg-slate-50 py-5 text-center text-sm font-bold text-slate-400">暂无确认记录。</p>
    </div>
  </section>
</template>
