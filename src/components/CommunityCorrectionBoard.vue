<script setup>
import { onMounted, ref } from 'vue'
import {
  fetchRejectedJuryItemsForReopen,
  reopenRejectedJuryCandidate
} from '../api/adminCapabilitiesService'

const props = defineProps({ isSuperAdmin: Boolean })
const items = ref([])
const isLoading = ref(false)
const errorMessage = ref('')
const activeId = ref('')
const notice = ref('')

const load = async () => {
  isLoading.value = true
  errorMessage.value = ''
  try {
    items.value = await fetchRejectedJuryItemsForReopen()
  } catch (error) {
    errorMessage.value = error.message || '纠错队列读取失败'
  } finally {
    isLoading.value = false
  }
}

const reopen = async item => {
  const reason = window.prompt(`请填写重新审理《${item.clothes_name}》的新证据或原因。原决定不会删除。`)?.trim()
  if (!reason) return
  activeId.value = item.candidate_id
  notice.value = ''
  try {
    const result = await reopenRejectedJuryCandidate(item.candidate_id, reason)
    notice.value = result?.status === 'awaiting_cosign'
      ? `已完成第 ${result.signature_count} / ${result.required_signatures} 份纠错共签，尚未重新打开。`
      : '原决定与共签历史已保留，该事项已重新进入既有重审 / 陪审流程。'
    await load()
  } catch (error) {
    window.alert(error.message || '发起纠错失败，请刷新后重试。')
  } finally {
    activeId.value = ''
  }
}

onMounted(load)
</script>

<template>
  <section class="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm md:p-6">
    <div class="mb-5 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h3 class="text-xl font-black text-slate-800">↩️ 永久驳回纠错</h3>
        <p class="mt-1 text-xs font-bold text-slate-500">原决定、理由、投票和共签记录都保留；{{ isSuperAdmin ? '站长可单独重新打开。' : '由 2 位未参与原流程的有效普通管理员共签后重新进入陪审。' }}</p>
      </div>
      <button class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-black text-slate-600" @click="load">刷新</button>
    </div>

    <p v-if="notice" class="mb-4 rounded-xl bg-emerald-50 p-3 text-sm font-bold text-emerald-700">{{ notice }}</p>
    <p v-if="isLoading" class="py-8 text-center font-bold text-slate-400">读取纠错事项中…</p>
    <p v-else-if="errorMessage" class="rounded-xl bg-rose-50 p-4 font-bold text-rose-700">{{ errorMessage }}</p>
    <p v-else-if="items.length === 0" class="rounded-xl bg-slate-50 py-8 text-center font-bold text-slate-400">暂无可重新审理的永久驳回事项。</p>

    <div v-else class="space-y-3">
      <article v-for="item in items" :key="item.candidate_id" class="flex flex-col justify-between gap-3 rounded-xl border border-slate-100 p-4 sm:flex-row sm:items-center">
        <div>
          <div class="font-black text-slate-800">《{{ item.clothes_name }}》</div>
          <div class="mt-1 text-xs font-bold text-slate-500">原驳回理由：{{ item.rejected_reason }} · {{ item.rejected_at ? new Date(item.rejected_at).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }) : '未知' }}</div>
          <div class="mt-2 text-xs font-black text-purple-700">纠错共签 {{ item.reopen_signature_count || 0 }} / 2</div>
        </div>
        <button class="rounded-lg border border-purple-200 px-4 py-2 text-sm font-black text-purple-700 disabled:opacity-50" :disabled="Boolean(activeId) || !item.can_reopen" @click="reopen(item)">{{ item.can_reopen ? '提交新证据并共签' : '因参与原流程不可纠错' }}</button>
      </article>
    </div>
  </section>
</template>
