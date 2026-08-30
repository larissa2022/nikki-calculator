<script setup>
import { onMounted, ref } from 'vue'
import {
  fetchCommunitySuitReviewQueue,
  reviewCommunitySuit
} from '../api/adminCapabilitiesService'

const props = defineProps({ isSuperAdmin: Boolean })
const items = ref([])
const isLoading = ref(false)
const errorMessage = ref('')
const activeName = ref('')
const notice = ref('')

const load = async () => {
  isLoading.value = true
  errorMessage.value = ''
  try {
    items.value = await fetchCommunitySuitReviewQueue()
  } catch (error) {
    errorMessage.value = error.message || '套装审核队列读取失败'
  } finally {
    isLoading.value = false
  }
}

const decide = async (item, decision) => {
  if (activeName.value) return
  let reason = null
  if (decision === 'reject') {
    reason = item.reject_reason || window.prompt(`请填写驳回《${item.name}》的理由；下一位管理员必须共签同一理由。`)?.trim()
    if (!reason) return
  } else if (!window.confirm(`确认${props.isSuperAdmin ? '通过' : '共签通过'}套装《${item.name}》吗？`)) {
    return
  }

  activeName.value = item.name
  notice.value = ''
  try {
    const result = await reviewCommunitySuit(item.name, decision, reason)
    notice.value = result?.status === 'awaiting_cosign'
      ? `《${item.name}》已完成第 ${result.signature_count} / ${result.required_signatures} 份共签，尚未改写正式库。`
      : `《${item.name}》已${result?.decision === 'rejected' ? '驳回' : '批准'}，正式状态已原子收口。`
    await load()
  } catch (error) {
    window.alert(error.message || '套装审核失败，请刷新后重试。')
  } finally {
    activeName.value = ''
  }
}

onMounted(load)
</script>

<template>
  <section class="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm md:p-6">
    <div class="mb-5 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h3 class="text-xl font-black text-slate-800">📦 套装共签审核</h3>
        <p class="mt-1 text-xs font-bold text-slate-500">
          {{ isSuperAdmin ? '站长可单独执行；所有决定继续留痕。' : '2 位不同的当前有效普通管理员必须对同一结论共签，达到门槛前不会写入正式套装。' }}
        </p>
      </div>
      <button class="rounded-lg border border-slate-200 px-3 py-2 text-xs font-black text-slate-600" @click="load">刷新</button>
    </div>

    <p v-if="notice" class="mb-4 rounded-xl bg-emerald-50 p-3 text-sm font-bold text-emerald-700">{{ notice }}</p>
    <p v-if="isLoading" class="py-8 text-center font-bold text-slate-400">读取套装申请中…</p>
    <p v-else-if="errorMessage" class="rounded-xl bg-rose-50 p-4 font-bold text-rose-700">{{ errorMessage }}</p>
    <p v-else-if="items.length === 0" class="rounded-xl bg-slate-50 py-8 text-center font-bold text-slate-400">暂无待审核套装。</p>

    <div v-else class="space-y-3">
      <article v-for="item in items" :key="item.name" class="rounded-xl border border-slate-100 p-4">
        <div class="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
          <div>
            <div class="font-black text-slate-800">《{{ item.name }}》 · {{ item.request_count }} 人申请</div>
            <div class="mt-1 text-xs font-bold text-slate-500">首次申请：{{ item.first_created_at ? new Date(item.first_created_at).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }) : '未知' }}</div>
            <div class="mt-2 flex flex-wrap gap-2 text-xs font-black">
              <span class="rounded-full bg-emerald-50 px-2 py-1 text-emerald-700">通过 {{ item.approve_signature_count || 0 }} / 2</span>
              <span class="rounded-full bg-rose-50 px-2 py-1 text-rose-700">驳回 {{ item.reject_signature_count || 0 }} / 2</span>
              <span v-if="item.my_decision" class="rounded-full bg-purple-50 px-2 py-1 text-purple-700">我已共签{{ item.my_decision === 'approve' ? '通过' : '驳回' }}</span>
            </div>
            <p v-if="item.reject_reason" class="mt-2 text-xs font-bold text-rose-600">现有驳回提案：{{ item.reject_reason }}</p>
          </div>
          <div class="flex shrink-0 gap-2">
            <button class="rounded-lg border border-rose-200 px-4 py-2 text-sm font-black text-rose-600 disabled:opacity-50" :disabled="Boolean(activeName) || item.my_decision === 'approve'" @click="decide(item, 'reject')">{{ item.reject_signature_count ? '共签驳回' : '发起驳回' }}</button>
            <button class="rounded-lg bg-blue-500 px-4 py-2 text-sm font-black text-white disabled:opacity-50" :disabled="Boolean(activeName) || item.my_decision === 'reject'" @click="decide(item, 'approve')">{{ item.approve_signature_count ? '共签通过' : '发起通过' }}</button>
          </div>
        </div>
      </article>
    </div>
  </section>
</template>
