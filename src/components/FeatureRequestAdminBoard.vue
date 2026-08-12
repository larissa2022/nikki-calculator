<script setup>
import { onMounted, reactive, ref } from 'vue'
import { fetchFeatureRequestsForAdmin, moderateFeatureRequest } from '../api/featureRequestService'
import {
  availableFeatureRequestAdminActions,
  featureRequestAdminAction,
  validateFeatureRequestAdminDecision
} from '../utils/featureRequests'

const rows = ref([])
const isLoading = ref(false)
const errorMessage = ref('')
const notice = ref('')
const actionId = ref('')
const forms = reactive({})

const ensureForm = requestId => {
  if (!forms[requestId]) forms[requestId] = { action: '', reason: '', publicResponse: '', duplicateOf: '' }
  return forms[requestId]
}

const statusLabel = status => ({ pending: '待评估', planned: '计划中', not_feasible: '技术无法实现' }[status] || '状态未知')
const visibilityLabel = visibility => ({ public: '公开', withdrawn: '已撤回', duplicate: '重复归档', hidden: '已隐藏' }[visibility] || '状态未知')

const availableActions = availableFeatureRequestAdminActions
const selectedAction = requestId => featureRequestAdminAction(ensureForm(requestId).action)
const duplicateOptions = requestId => rows.value.filter(item => (
  item.requestId !== requestId && item.visibility === 'public'
))

const selectAction = (requestId, action) => {
  const form = ensureForm(requestId)
  form.action = action
  if (action !== 'mark_duplicate') form.duplicateOf = ''
  if (!['plan', 'not_feasible'].includes(action)) form.publicResponse = ''
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

const handle = async item => {
  const form = ensureForm(item.requestId)
  const validationError = validateFeatureRequestAdminDecision(form)
  if (validationError) return window.alert(validationError)

  actionId.value = item.requestId
  notice.value = ''
  try {
    await moderateFeatureRequest({
      requestId: item.requestId,
      action: form.action,
      reason: form.reason.trim(),
      publicResponse: form.publicResponse.trim() || null,
      duplicateOf: form.duplicateOf.trim() || null
    })
    notice.value = '建议处理结果已保存并记录审计事件。'
    forms[item.requestId] = { action: '', reason: '', publicResponse: '', duplicateOf: '' }
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
      <div v-if="availableActions(item).length" class="decision-panel">
        <strong class="panel-title">1. 选择处理动作</strong>
        <p class="panel-help">选择后不会立即生效；请继续填写所需信息并确认。</p>
        <div class="actions">
        <button
          v-for="action in availableActions(item)"
          :key="action.value"
          :class="{ selected: ensureForm(item.requestId).action === action.value }"
          :disabled="actionId === item.requestId"
          @click="selectAction(item.requestId, action.value)"
        >{{ action.label }}</button>
        </div>

        <div v-if="selectedAction(item.requestId)" class="fields">
          <strong class="panel-title">2. 填写处理信息</strong>
          <label>
            内部处理记录 <em>必填 · 仅管理员可见</em>
            <input
              v-model="ensureForm(item.requestId).reason"
              maxlength="500"
              placeholder="例如：已评估开发成本，纳入下个版本"
            />
          </label>
          <label v-if="selectedAction(item.requestId).publicResponse">
            给用户看的公开说明
            <em>{{ selectedAction(item.requestId).publicResponse === 'required' ? '必填' : '选填' }} · 会显示在公开建议页</em>
            <textarea
              v-model="ensureForm(item.requestId).publicResponse"
              maxlength="1000"
              rows="3"
              placeholder="例如：已加入开发计划，预计在后续版本提供"
            ></textarea>
          </label>
          <label v-if="selectedAction(item.requestId).duplicateTarget">
            重复的原建议 <em>必选 · 用户应继续为原建议点赞</em>
            <select v-model="ensureForm(item.requestId).duplicateOf">
              <option value="">请选择公开的原建议</option>
              <option
                v-for="option in duplicateOptions(item.requestId)"
                :key="option.requestId"
                :value="option.requestId"
              >{{ option.title }}（{{ option.likeCount }} 赞）</option>
            </select>
            <small v-if="duplicateOptions(item.requestId).length === 0">当前没有其他公开建议可作为重复目标。</small>
          </label>

          <button
            class="confirm-action"
            :disabled="actionId === item.requestId"
            @click="handle(item)"
          >{{ actionId === item.requestId ? '正在保存…' : selectedAction(item.requestId).confirmLabel }}</button>
        </div>
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
.decision-panel { display: grid; gap: 9px; margin-top: 14px; padding: 14px; border-radius: 12px; background: #fafafa; }
.panel-title { color: #334155; font-size: 12px; }
.panel-help { color: #94a3b8 !important; }
.fields { display: grid; gap: 12px; margin-top: 5px; padding-top: 12px; border-top: 1px solid #e2e8f0; }
label { display: grid; gap: 5px; color: #475569; font-size: 11px; font-weight: 900; }
label em { color: #94a3b8; font-size: 10px; font-style: normal; font-weight: 700; }
input, textarea, select { box-sizing: border-box; width: 100%; padding: 10px; border: 1px solid #cbd5e1; border-radius: 8px; background: #fff; font: inherit; }
small { color: #be123c; font-size: 10px; }
.actions { display: flex; flex-wrap: wrap; gap: 7px; margin-top: 12px; }
.actions button { padding: 8px 10px; border: 0; border-radius: 8px; background: #ede9fe; color: #6d28d9; font-weight: 900; cursor: pointer; }
.actions button.selected { background: #6d28d9; color: #fff; box-shadow: 0 0 0 3px rgba(109,40,217,.14); }
.confirm-action { justify-self: start; padding: 10px 14px; border: 0; border-radius: 8px; background: #6d28d9; color: #fff; font-weight: 900; cursor: pointer; }
.actions button:disabled { opacity: .5; }
@media (max-width: 640px) { .summary { display: grid; } }
</style>
