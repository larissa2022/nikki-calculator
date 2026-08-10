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

const props = defineProps({ users: { type: Array, default: () => [] } })

const data = ref({ terms: [], exclusions: [], candidates: [], decisions: [] })
const isLoading = ref(false)
const errorMessage = ref('')
const activeSection = ref('terms')
const manualForm = reactive({ userId: '', reason: '', endsAt: '' })
const exclusionForm = reactive({ userId: '', reason: '', startsAt: '', endsAt: '' })
const actionNotice = ref('')

const activeTerms = computed(() => data.value.terms.filter(term => term.status === 'active' && new Date(term.scheduled_end_at) > new Date()))
const groupedExclusions = computed(() => groupCandidateExclusions(data.value.exclusions))
const currentExclusions = computed(() => groupedExclusions.value.current)
const exclusionHistory = computed(() => groupedExclusions.value.history)

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

const load = async () => {
  isLoading.value = true
  errorMessage.value = ''
  try {
    data.value = await fetchAdminGovernance()
  } catch (error) {
    errorMessage.value = error.message || '管理员治理数据读取失败'
  } finally {
    isLoading.value = false
  }
}

const submitManual = async () => {
  if (!manualForm.userId.trim() || !manualForm.reason.trim() || !manualForm.endsAt) return window.alert('请完整填写用户 UUID、原因和结束时间。')
  try {
    await createManualAdminTerm({
      userId: manualForm.userId.trim(),
      reason: manualForm.reason.trim(),
      endsAt: new Date(manualForm.endsAt).toISOString()
    })
    Object.assign(manualForm, { userId: '', reason: '', endsAt: '' })
    await load()
  } catch (error) {
    window.alert(error.message || '手动任期创建失败')
  }
}

const stopTerm = async (term) => {
  const reason = window.prompt(`请填写提前结束「${term.display_name}」任期的原因：`)?.trim()
  if (!reason) return
  try {
    await endAdminTerm(term.id, reason)
    await load()
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
    await createAdminCandidateExclusion({
      userId: exclusionForm.userId.trim(),
      reason: exclusionForm.reason.trim(),
      startsAt: startsAt.toISOString(),
      endsAt: endsAt.toISOString()
    })
    Object.assign(exclusionForm, { userId: '', reason: '', startsAt: '', endsAt: '' })
    await load()
    actionNotice.value = '候选排除已创建，可在下方“当前及待生效排除”中撤销。'
  } catch (error) {
    window.alert(error.message || '候选排除创建失败')
  }
}

const revokeExclusion = async (item) => {
  if (!window.confirm(`确认撤销「${item.display_name}」的候选排除吗？`)) return
  try {
    await revokeAdminCandidateExclusion(item.id)
    await load()
    actionNotice.value = '候选排除已撤销，记录已保留在历史中。'
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
        <h3 class="text-xl font-black text-slate-800">🛡️ 管理员任期治理</h3>
        <p class="mt-1 text-xs font-bold text-slate-500">维护最长 31 天手动任期、显式候选排除，并查看冻结候选和不可变审核审计。</p>
      </div>
      <button class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-black text-slate-600" @click="load">刷新</button>
    </div>

    <div class="mb-5 flex flex-wrap gap-2">
      <button v-for="item in [{key:'terms',label:'任期'}, {key:'exclusions',label:'候选排除'}, {key:'candidates',label:'候选快照'}, {key:'decisions',label:'审核审计'}]" :key="item.key" class="rounded-full px-4 py-2 text-xs font-black" :class="activeSection === item.key ? 'bg-purple-600 text-white' : 'bg-slate-100 text-slate-600'" @click="activeSection = item.key">{{ item.label }}</button>
    </div>

    <p v-if="isLoading" class="py-8 text-center font-bold text-slate-400">读取中…</p>
    <p v-else-if="errorMessage" class="rounded-xl bg-rose-50 p-4 font-bold text-rose-700">{{ errorMessage }}</p>

    <template v-else-if="activeSection === 'terms'">
      <form class="mb-5 grid grid-cols-1 gap-3 rounded-xl bg-slate-50 p-4 md:grid-cols-2" @submit.prevent="submitManual">
        <select v-model="manualForm.userId" class="rounded-lg border border-slate-200 px-3 py-2 text-sm">
          <option value="">选择用户</option>
          <option v-for="user in props.users" :key="user.id" :value="user.id">{{ user.username || user.nickname || '未命名用户' }}</option>
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
          <option v-for="user in props.users" :key="user.id" :value="user.id">{{ user.username || user.nickname || '未命名用户' }}</option>
        </select>
        <label class="text-xs font-black text-slate-600">开始时间<input v-model="exclusionForm.startsAt" type="datetime-local" class="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm font-normal" /></label>
        <label class="text-xs font-black text-slate-600">结束时间<input v-model="exclusionForm.endsAt" type="datetime-local" class="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm font-normal" /></label>
        <input v-model="exclusionForm.reason" class="rounded-lg border border-slate-200 px-3 py-2 text-sm md:col-span-2" placeholder="排除原因（必填）" />
        <button class="rounded-lg bg-purple-600 px-4 py-2 text-sm font-black text-white md:col-span-2">新增候选排除</button>
      </form>
      <p v-if="actionNotice" class="mb-4 rounded-xl bg-emerald-50 p-3 text-sm font-bold text-emerald-700">{{ actionNotice }}</p>

      <div class="mb-6">
        <h4 class="mb-3 text-sm font-black text-slate-700">当前及待生效排除（{{ currentExclusions.length }}）</h4>
        <div class="space-y-3">
          <article v-for="item in currentExclusions" :key="item.id" class="flex flex-col justify-between gap-3 rounded-xl border border-slate-100 p-4 md:flex-row md:items-center">
            <div>
              <div class="flex flex-wrap items-center gap-2"><span class="font-black text-slate-800">{{ item.display_name }}</span><span class="rounded-full px-2 py-1 text-[11px] font-black" :class="exclusionStatusClass(item.view_status)">{{ exclusionStatusLabel(item.view_status) }}</span></div>
              <div class="mt-1 text-xs font-bold text-slate-500">{{ item.reason }} · {{ formatTime(item.starts_at) }} 至 {{ formatTime(item.ends_at) }}</div>
            </div>
            <button class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-black text-slate-600" @click="revokeExclusion(item)">撤销排除</button>
          </article>
          <p v-if="currentExclusions.length === 0" class="rounded-xl bg-slate-50 py-5 text-center text-sm font-bold text-slate-400">暂无可撤销的候选排除。</p>
        </div>
      </div>

      <div>
        <h4 class="mb-3 text-sm font-black text-slate-700">排除历史（{{ exclusionHistory.length }}）</h4>
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

    <div v-else class="space-y-3">
      <article v-for="item in data.decisions" :key="item.id" class="rounded-xl border border-slate-100 p-4 text-sm"><div class="font-black" :class="item.action === 'approved' ? 'text-emerald-700' : 'text-rose-700'">{{ item.action === 'approved' ? '通过' : '驳回' }} · {{ item.adopted_payload?.name || '未命名服装' }}</div><div class="mt-1 text-xs font-bold text-slate-500">审核者 {{ item.reviewer_display_name }}<span v-if="item.term_source"> · {{ sourceLabel(item.term_source) }}至 {{ formatTime(item.term_ends_at) }}</span> · 采用 {{ item.adopted_count }} / 全部来源 {{ item.source_count }} · {{ formatTime(item.created_at) }}<span v-if="item.reason"> · {{ item.reason }}</span></div></article>
    </div>
  </section>
</template>
