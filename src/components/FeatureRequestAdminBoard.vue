<script setup>
import { onMounted, reactive, ref } from 'vue'
import { fetchFeatureRequestsForAdmin, moderateFeatureRequest } from '../api/featureRequestService'

const rows = ref([])
const isLoading = ref(false)
const errorMessage = ref('')
const notice = ref('')
const actionId = ref('')
const forms = reactive({})

const ensureForm = requestId => {
  if (!forms[requestId]) forms[requestId] = { reason: '', publicResponse: '', duplicateOf: '' }
  return forms[requestId]
}

const statusLabel = status => ({ pending: '待评估', planned: '计划中', not_feasible: '技术无法实现' }[status] || '状态未知')
const visibilityLabel = visibility => ({ public: '公开', withdrawn: '已撤回', duplicate: '重复归档', hidden: '已隐藏' }[visibility] || '状态未知')

const availableActions = item => {
  if (item.visibility === 'hidden' || item.visibility === 'duplicate') {
    return [{ value: 'restore', label: '恢复公开' }]
  }
  if (item.visibility !== 'public') return []
  if (item.status === 'pending') {
    return [
      { value: 'plan', label: '计划中' },
      { value: 'not_feasible', label: '技术无法实现' },
      { value: 'mark_duplicate', label: '重复归档' },
      { value: 'hide', label: '隐藏' }
    ]
  }
  return [
    { value: 'reopen', label: '重新评估' },
    { value: 'hide', label: '隐藏' }
  ]
}

const load = async () => {
  isLoading.value = true
  errorMessage.value = ''
  try {
    rows.value = await fetchFeatureRequestsForAdmin()
    rows.value.forEach(item => ensureForm(item.requestId))
  } catch (error) {
    errorMessage.value = error.message || '建议治理队列读取失败。'
  } finally {
    isLoading.value = false
  }
}

const handle = async (item, action) => {
  const form = ensureForm(item.requestId)
  if (form.reason.trim().length < 2) return window.alert('请填写至少 2 个字的处理原因。')
  if (action === 'not_feasible' && !form.publicResponse.trim()) return window.alert('技术无法实现必须填写公开说明。')
  if (action === 'mark_duplicate' && !form.duplicateOf.trim()) return window.alert('请填写重复目标建议 UUID。')

  actionId.value = item.requestId
  notice.value = ''
  try {
    await moderateFeatureRequest({
      requestId: item.requestId,
      action,
      reason: form.reason.trim(),
      publicResponse: form.publicResponse.trim() || null,
      duplicateOf: form.duplicateOf.trim() || null
    })
    notice.value = '建议处理结果已保存并记录审计事件。'
    await load()
  } catch (error) {
    notice.value = error.message || '建议处理失败。'
  } finally {
    actionId.value = ''
  }
}

onMounted(() => { void load() })
</script>

<template>
  <section class="admin-board">
    <header>
      <h2>优化建议治理</h2>
      <p>仅超级管理员可处理。点赞只决定待评估列表顺序，不等同于开发承诺。</p>
    </header>
    <div v-if="notice" class="notice">{{ notice }}</div>
    <div v-if="isLoading" class="state">正在读取建议…</div>
    <div v-else-if="errorMessage" class="state error">{{ errorMessage }}</div>
    <div v-else-if="rows.length === 0" class="state">暂无建议。</div>
    <article v-for="item in rows" :key="item.requestId" class="admin-card">
      <div class="summary">
        <div>
          <strong>{{ item.title }}</strong>
          <span>{{ statusLabel(item.status) }} · {{ visibilityLabel(item.visibility) }} · {{ item.likeCount }} 赞</span>
        </div>
        <code>{{ item.requestId }}</code>
      </div>
      <p>{{ item.description }}</p>
      <p v-if="item.authorName" class="identity">内部作者：{{ item.authorName }}</p>
      <div v-if="availableActions(item).length" class="fields">
        <label>内部原因<input v-model="ensureForm(item.requestId).reason" maxlength="500" /></label>
        <label>公开说明<textarea v-model="ensureForm(item.requestId).publicResponse" maxlength="1000" rows="2"></textarea></label>
        <label>重复目标 UUID<input v-model="ensureForm(item.requestId).duplicateOf" /></label>
      </div>
      <div v-if="availableActions(item).length" class="actions">
        <button
          v-for="action in availableActions(item)"
          :key="action.value"
          :disabled="actionId === item.requestId"
          @click="handle(item, action.value)"
        >{{ action.label }}</button>
      </div>
      <p v-else class="closed-note">该记录已由提交者撤回，仅保留审计，不再提供治理动作。</p>
    </article>
  </section>
</template>

<style scoped>
.admin-board { display: grid; gap: 14px; }
header, .admin-card { padding: 18px; border: 1px solid #e2e8f0; border-radius: 16px; background: #fff; }
header h2 { margin: 0 0 6px; color: #1e293b; }
header p, .admin-card p { margin: 0; color: #64748b; font-size: 12px; line-height: 1.7; }
.notice, .state { padding: 12px; border-radius: 10px; background: #f5f3ff; color: #6d28d9; font-weight: 800; }
.error { background: #fff1f2; color: #be123c; }
.summary { display: flex; justify-content: space-between; gap: 12px; margin-bottom: 10px; }
.summary div { display: grid; gap: 4px; }
.summary span, code, .identity { color: #94a3b8; font-size: 10px; }
.closed-note { margin-top: 12px !important; padding: 9px; border-radius: 8px; background: #f8fafc; }
code { word-break: break-all; }
.fields { display: grid; gap: 8px; margin-top: 12px; }
label { display: grid; gap: 4px; color: #475569; font-size: 11px; font-weight: 900; }
input, textarea { box-sizing: border-box; width: 100%; padding: 9px; border: 1px solid #cbd5e1; border-radius: 8px; font: inherit; }
.actions { display: flex; flex-wrap: wrap; gap: 7px; margin-top: 12px; }
.actions button { padding: 8px 10px; border: 0; border-radius: 8px; background: #ede9fe; color: #6d28d9; font-weight: 900; cursor: pointer; }
.actions button:disabled { opacity: .5; }
@media (max-width: 640px) { .summary { display: grid; } }
</style>
