<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import {
  FEATURE_REQUEST_FILTER,
  fetchFeatureRequests,
  fetchMyFeatureRequests,
  setFeatureRequestLike,
  submitFeatureRequest,
  withdrawFeatureRequest
} from '../api/featureRequestService'

const props = defineProps({ isLoggedIn: Boolean, userId: { type: String, default: '' } })

const activeFilter = ref(FEATURE_REQUEST_FILTER.PENDING)
const rows = ref([])
const myRows = ref([])
const isLoading = ref(false)
const actionId = ref('')
const errorMessage = ref('')
const notice = ref('')
const form = reactive({ title: '', description: '' })

const filters = [
  { value: FEATURE_REQUEST_FILTER.PENDING, label: '待评估' },
  { value: FEATURE_REQUEST_FILTER.PLANNED, label: '计划中' },
  { value: FEATURE_REQUEST_FILTER.NOT_FEASIBLE, label: '技术无法实现' }
]

const canSubmit = computed(() => (
  props.isLoggedIn
  && form.title.trim().length >= 5
  && form.title.trim().length <= 80
  && form.description.trim().length >= 10
  && form.description.trim().length <= 1000
  && !actionId.value
))

const statusLabel = status => ({
  pending: '待评估',
  planned: '计划中',
  not_feasible: '技术无法实现'
}[status] || '状态未知')

const visibilityLabel = visibility => ({
  public: '公开',
  withdrawn: '已撤回',
  duplicate: '重复归档',
  hidden: '已隐藏'
}[visibility] || '状态未知')

const formatTime = value => value
  ? new Intl.DateTimeFormat('zh-CN', {
      timeZone: 'Asia/Shanghai',
      year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit'
    }).format(new Date(value))
  : '时间未知'

const load = async ({ background = false } = {}) => {
  if (!background) isLoading.value = true
  errorMessage.value = ''
  try {
    const [publicRows, ownRows] = await Promise.all([
      fetchFeatureRequests(activeFilter.value),
      props.isLoggedIn ? fetchMyFeatureRequests() : Promise.resolve([])
    ])
    rows.value = publicRows
    myRows.value = ownRows
  } catch (error) {
    errorMessage.value = error.message || '优化建议暂时无法读取，请稍后重试。'
  } finally {
    isLoading.value = false
  }
}

const submit = async () => {
  if (!canSubmit.value) return
  actionId.value = 'submit'
  notice.value = ''
  try {
    const result = await submitFeatureRequest(form.title.trim(), form.description.trim())
    notice.value = result?.duplicate
      ? '已有完全相同的公开建议，请在对应状态列表中直接点赞。'
      : '优化建议已提交，等待开发者评估。'
    form.title = ''
    form.description = ''
    activeFilter.value = FEATURE_REQUEST_FILTER.PENDING
    await load({ background: true })
  } catch (error) {
    notice.value = error.message || '优化建议提交失败。'
  } finally {
    actionId.value = ''
  }
}

const toggleLike = async item => {
  if (!props.isLoggedIn) {
    notice.value = '请先登录后点赞。'
    return
  }
  actionId.value = `like:${item.requestId}`
  notice.value = ''
  try {
    await setFeatureRequestLike(item.requestId, !item.hasLiked)
    await load({ background: true })
  } catch (error) {
    notice.value = error.message || '点赞操作失败。'
  } finally {
    actionId.value = ''
  }
}

const withdraw = async item => {
  if (!window.confirm(`确认撤回“${item.title}”？撤回后内容不可恢复为作者可操作状态。`)) return
  actionId.value = `withdraw:${item.requestId}`
  notice.value = ''
  try {
    await withdrawFeatureRequest(item.requestId)
    notice.value = '建议已撤回，公开列表不再展示，审计事实继续保留。'
    await load({ background: true })
  } catch (error) {
    notice.value = error.message || '撤回失败。'
  } finally {
    actionId.value = ''
  }
}

watch(activeFilter, () => { void load() })
watch(() => props.userId, () => { void load() })
onMounted(() => { void load() })
</script>

<template>
  <section class="feature-board" aria-labelledby="feature-board-title">
    <header class="feature-hero">
      <p class="eyebrow">产品共建</p>
      <h2 id="feature-board-title">优化建议</h2>
      <p>公开查看社区建议；登录后可提交和点赞。点赞只用于产品排序参考，不代表开发承诺，也不影响积分或陪审票。</p>
    </header>

    <form v-if="isLoggedIn" class="submit-card" @submit.prevent="submit">
      <h3>提交新建议</h3>
      <label>
        <span>标题</span>
        <input v-model="form.title" maxlength="80" placeholder="用一句话说明想优化什么" />
        <small>{{ form.title.trim().length }} / 80，至少 5 字</small>
      </label>
      <label>
        <span>说明</span>
        <textarea v-model="form.description" maxlength="1000" rows="5" placeholder="说明使用场景、当前不便和希望达到的结果"></textarea>
        <small>{{ form.description.trim().length }} / 1000，至少 10 字</small>
      </label>
      <button class="primary-btn" type="submit" :disabled="!canSubmit">
        {{ actionId === 'submit' ? '正在提交…' : '提交优化建议' }}
      </button>
      <p class="form-help">提交后正文不可编辑；每个北京自然日最多提交 5 条。</p>
    </form>
    <div v-else class="login-hint">登录后可以提交建议、点赞和取消点赞。</div>

    <div v-if="notice" class="notice" role="status">{{ notice }}</div>

    <nav class="filter-tabs" aria-label="建议状态筛选">
      <button
        v-for="filter in filters"
        :key="filter.value"
        type="button"
        :class="{ active: activeFilter === filter.value }"
        @click="activeFilter = filter.value"
      >{{ filter.label }}</button>
    </nav>

    <div v-if="isLoading" class="state-card">正在读取优化建议…</div>
    <div v-else-if="errorMessage" class="state-card error-state">
      <span>{{ errorMessage }}</span>
      <button type="button" @click="load()">重新读取</button>
    </div>
    <div v-else-if="rows.length === 0" class="state-card">当前状态还没有公开建议。</div>
    <div v-else class="request-list">
      <article v-for="item in rows" :key="item.requestId" class="request-card">
        <div class="request-main">
          <div class="request-heading">
            <h3>{{ item.title }}</h3>
            <span :class="['status-badge', item.status]">{{ statusLabel(item.status) }}</span>
          </div>
          <p class="description">{{ item.description }}</p>
          <p v-if="item.publicResponse" class="developer-response"><strong>开发者说明：</strong>{{ item.publicResponse }}</p>
          <time :datetime="item.createdAt || undefined">提交于 {{ formatTime(item.createdAt) }}</time>
        </div>
        <button
          type="button"
          class="like-btn"
          :class="{ liked: item.hasLiked }"
          :disabled="actionId === `like:${item.requestId}`"
          :aria-pressed="item.hasLiked"
          @click="toggleLike(item)"
        >
          <span aria-hidden="true">♥</span>
          <strong>{{ item.likeCount }}</strong>
          <small>{{ item.hasLiked ? '取消点赞' : '点赞' }}</small>
        </button>
      </article>
    </div>

    <section v-if="isLoggedIn" class="my-section" aria-labelledby="my-feature-requests">
      <h3 id="my-feature-requests">我的建议</h3>
      <p v-if="myRows.length === 0" class="empty-inline">还没有提交建议。</p>
      <article v-for="item in myRows" :key="`mine:${item.requestId}`" class="my-card">
        <div>
          <strong>{{ item.title }}</strong>
          <span>{{ statusLabel(item.status) }} · {{ visibilityLabel(item.visibility) }} · {{ item.likeCount }} 赞</span>
        </div>
        <button
          v-if="item.canWithdraw"
          type="button"
          :disabled="actionId === `withdraw:${item.requestId}`"
          @click="withdraw(item)"
        >撤回</button>
      </article>
    </section>
  </section>
</template>

<style scoped>
.feature-board { display: grid; gap: 18px; animation: fadeIn .35s ease; }
.feature-hero, .submit-card, .request-card, .my-section { padding: 18px; border: 1px solid #f1f5f9; border-radius: 18px; background: rgba(255,255,255,.92); box-shadow: 0 6px 18px rgba(148,163,184,.08); }
.eyebrow { margin: 0 0 4px; color: #db2777; font-size: 11px; font-weight: 900; letter-spacing: .12em; }
h2, h3, p { margin-top: 0; }
h2 { margin-bottom: 7px; color: #1e293b; font-size: 24px; }
.feature-hero > p:last-child, .form-help { margin-bottom: 0; color: #64748b; font-size: 12px; font-weight: 650; line-height: 1.7; }
.submit-card { display: grid; gap: 12px; }
.submit-card label { display: grid; gap: 6px; color: #475569; font-size: 12px; font-weight: 900; }
input, textarea { box-sizing: border-box; width: 100%; padding: 11px 12px; border: 1.5px solid #e2e8f0; border-radius: 11px; color: #334155; font: inherit; resize: vertical; }
input:focus, textarea:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244,114,182,.12); outline: 0; }
small { color: #94a3b8; font-size: 10px; }
.primary-btn { padding: 12px; border: 0; border-radius: 10px; background: linear-gradient(135deg,#f472b6,#d946ef); color: #fff; font-weight: 900; cursor: pointer; }
button:disabled { opacity: .55; cursor: not-allowed; }
.login-hint, .notice, .state-card { padding: 14px; border-radius: 12px; background: #f8fafc; color: #64748b; font-size: 12px; font-weight: 750; text-align: center; }
.notice { background: #fff7ed; color: #c2410c; }
.error-state { color: #be123c; }
.error-state button { margin-left: 8px; }
.filter-tabs { display: flex; gap: 8px; overflow-x: auto; }
.filter-tabs button { flex: 0 0 auto; padding: 9px 13px; border: 1px solid #e2e8f0; border-radius: 999px; background: #fff; color: #64748b; font-weight: 900; cursor: pointer; }
.filter-tabs button.active { border-color: #f9a8d4; background: #fdf2f8; color: #be185d; }
.request-list { display: grid; gap: 12px; }
.request-card { display: grid; grid-template-columns: 1fr auto; gap: 14px; }
.request-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; }
.request-heading h3 { margin-bottom: 8px; color: #334155; font-size: 16px; }
.description { color: #475569; font-size: 13px; line-height: 1.7; white-space: pre-wrap; word-break: break-word; }
.developer-response { padding: 10px; border-radius: 10px; background: #f5f3ff; color: #6d28d9; font-size: 12px; line-height: 1.6; }
time { color: #94a3b8; font-size: 10px; font-weight: 700; }
.status-badge { flex: 0 0 auto; padding: 4px 8px; border-radius: 999px; background: #fef3c7; color: #b45309; font-size: 10px; font-weight: 900; }
.status-badge.planned { background: #dcfce7; color: #15803d; }
.status-badge.not_feasible { background: #f1f5f9; color: #64748b; }
.like-btn { display: grid; align-content: center; justify-items: center; min-width: 66px; padding: 9px; border: 1px solid #fecdd3; border-radius: 14px; background: #fff1f2; color: #e11d48; cursor: pointer; }
.like-btn span { font-size: 18px; }
.like-btn strong { font-size: 16px; }
.like-btn.liked { background: #e11d48; color: white; }
.my-section { display: grid; gap: 9px; }
.my-card { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 11px; border-radius: 11px; background: #f8fafc; }
.my-card div { display: grid; gap: 4px; }
.my-card span { color: #64748b; font-size: 10px; font-weight: 750; }
.my-card button { padding: 7px 10px; border: 0; border-radius: 8px; background: #ffe4e6; color: #be123c; font-weight: 900; cursor: pointer; }
.empty-inline { margin: 0; color: #94a3b8; font-size: 12px; }
@media (max-width: 560px) { .request-card { grid-template-columns: 1fr; } .like-btn { grid-template-columns: auto auto auto; gap: 6px; } .request-heading { display: grid; } }
</style>
