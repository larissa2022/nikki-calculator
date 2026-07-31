<script setup>
import { onMounted, ref } from 'vue'
import {
  fetchLowRiskReviewCandidates,
  reviewLowRiskCandidate
} from '../api/adminCapabilitiesService'

defineProps({ adminCapabilities: { type: Object, required: true } })
const emit = defineEmits(['back-to-main'])

const candidates = ref([])
const isLoading = ref(false)
const activeCandidateId = ref(null)
const errorMessage = ref('')

const loadCandidates = async () => {
  isLoading.value = true
  errorMessage.value = ''
  try {
    candidates.value = await fetchLowRiskReviewCandidates()
  } catch (error) {
    errorMessage.value = error.message || '低风险审核列表读取失败'
  } finally {
    isLoading.value = false
  }
}

const decide = async (candidate, action) => {
  if (activeCandidateId.value) return
  let reason = null
  if (action === 'rejected') {
    reason = window.prompt('请填写驳回原因。提交人将看到原因并可重新提交。')?.trim()
    if (!reason) return
  } else if (!window.confirm(`确认按 ${candidate.supporter_count} 位用户支持的多数资料通过《${candidate.name}》吗？`)) {
    return
  }

  activeCandidateId.value = candidate.representative_pending_id
  try {
    await reviewLowRiskCandidate(candidate.representative_pending_id, action, reason)
    await loadCandidates()
    window.alert(action === 'approved' ? '多数资料已入库，少数不同意见仍保留。' : '多数资料已驳回，提交人可按原因重新提交。')
  } catch (error) {
    window.alert(error.message || '审核失败，请刷新后重试。')
  } finally {
    activeCandidateId.value = null
  }
}

onMounted(loadCandidates)
</script>

<template>
  <div class="admin-container pb-20 max-w-4xl mx-auto">
    <div class="mb-6 flex flex-col gap-3 rounded-2xl border border-slate-100 bg-white p-5 shadow-sm md:flex-row md:items-center md:justify-between">
      <div>
        <h2 class="text-xl font-black text-slate-800">新增服装多数审核</h2>
        <p class="mt-1 text-sm font-bold text-slate-500">只展示数据库实时复核通过的低风险事项：至少 5 位有效用户支持、无并列、正式库不存在且您未参与提交。</p>
      </div>
      <button class="text-sm font-bold text-slate-500 hover:text-slate-800" @click="emit('back-to-main')">🏠 返回前台</button>
    </div>

    <div class="mb-5 rounded-xl border border-purple-100 bg-purple-50 p-4 text-sm font-bold text-purple-800">
      当前是受限普通管理员界面。套装、正式库补全、重审、报错、永久驳回和用户权限管理均不在您的权限范围内。
    </div>

    <div v-if="isLoading" class="rounded-2xl bg-white p-10 text-center font-bold text-slate-400">正在复核候选…</div>
    <div v-else-if="errorMessage" class="rounded-2xl border border-rose-200 bg-rose-50 p-5 text-rose-700">
      {{ errorMessage }}
      <button class="ml-3 font-black underline" @click="loadCandidates">重试</button>
    </div>
    <div v-else-if="candidates.length === 0" class="rounded-2xl bg-white p-10 text-center font-bold text-slate-400">当前没有符合条件的低风险新增服装。</div>
    <div v-else class="grid grid-cols-1 gap-4 md:grid-cols-2">
      <article v-for="candidate in candidates" :key="candidate.candidate_key" class="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h3 class="text-lg font-black text-slate-800">{{ candidate.name }}</h3>
            <p class="mt-1 text-xs font-bold text-slate-500">{{ candidate.category }} · 短编号 {{ candidate.game_id }} · {{ candidate.stars }} 星</p>
          </div>
          <span class="shrink-0 rounded-full bg-emerald-50 px-3 py-1 text-xs font-black text-emerald-700">{{ candidate.supporter_count }} 人支持</span>
        </div>
        <p v-if="candidate.minority_count" class="mt-3 rounded-lg bg-amber-50 p-3 text-xs font-bold text-amber-700">另有 {{ candidate.minority_count }} 条不同意见；本次只处理多数资料，少数意见继续保留。</p>
        <div class="mt-4 flex gap-3">
          <button class="flex-1 rounded-xl border border-rose-200 px-4 py-2 text-sm font-black text-rose-600 disabled:opacity-50" :disabled="Boolean(activeCandidateId)" @click="decide(candidate, 'rejected')">填写原因并驳回</button>
          <button class="flex-1 rounded-xl bg-purple-600 px-4 py-2 text-sm font-black text-white disabled:opacity-50" :disabled="Boolean(activeCandidateId)" @click="decide(candidate, 'approved')">按多数通过</button>
        </div>
      </article>
    </div>
  </div>
</template>
