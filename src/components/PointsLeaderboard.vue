<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { supabase } from '../api/supabase'
import { fetchPointsLeaderboard } from '../api/pointsService'

const PERIODS = [
  { key: 'total', label: '总榜', description: '统计全部已生效积分' },
  { key: 'current_month', label: '当月榜', description: '按北京时间统计本月已生效积分' },
  { key: 'last_month', label: '上月榜', description: '这里展示上个月最终确定的积分和排名' }
]
const PAGE_SIZE = 20

const activePeriod = ref('total')
const currentPage = ref(1)
const states = reactive({
  total: { rows: [], isLoading: false, loadError: false, loaded: false },
  current_month: { rows: [], isLoading: false, loadError: false, loaded: false },
  last_month: { rows: [], isLoading: false, loadError: false, loaded: false }
})

const activeState = computed(() => states[activePeriod.value])
const activeDefinition = computed(() => (
  PERIODS.find(period => period.key === activePeriod.value) || PERIODS[0]
))
const totalPages = computed(() => Math.max(1, Math.ceil(activeState.value.rows.length / PAGE_SIZE)))
const emptyDescription = computed(() => (
  activePeriod.value === 'last_month'
    ? '上一个完整自然月没有已生效积分。'
    : '新的有效贡献和审核积分生效后会显示在这里。'
))
const visibleRows = computed(() => {
  const start = (currentPage.value - 1) * PAGE_SIZE
  return activeState.value.rows.slice(start, start + PAGE_SIZE)
})

const loadLeaderboard = async (period = activePeriod.value, { force = false } = {}) => {
  const state = states[period]
  if (!state || state.isLoading || (state.loaded && !force)) return

  state.isLoading = true
  state.loadError = false

  try {
    state.rows = await fetchPointsLeaderboard(supabase, period)
    state.loaded = true
  } catch (error) {
    console.error('读取积分排行榜失败:', error)
    state.rows = []
    state.loadError = true
  } finally {
    state.isLoading = false
  }
}

const switchPeriod = (period) => {
  activePeriod.value = period
}

const retryCurrentPeriod = () => {
  loadLeaderboard(activePeriod.value, { force: true })
}

const rankBadge = (rank) => {
  if (rank === 1) return '🥇'
  if (rank === 2) return '🥈'
  if (rank === 3) return '🥉'
  return String(rank)
}

const formatPoints = (points) => new Intl.NumberFormat('zh-CN').format(points)

watch(activePeriod, period => {
  currentPage.value = 1
  loadLeaderboard(period)
})
watch(totalPages, nextTotal => {
  if (currentPage.value > nextTotal) currentPage.value = nextTotal
})

onMounted(() => loadLeaderboard())
</script>

<template>
  <section class="leaderboard" aria-labelledby="points-leaderboard-title">
    <header class="leaderboard-header">
      <div>
        <p class="eyebrow">社区贡献积分</p>
        <h2 id="points-leaderboard-title">积分排行榜</h2>
        <p class="description">{{ activeDefinition.description }}；积分相同的玩家会并列显示。</p>
      </div>
      <div class="period-tabs" role="tablist" aria-label="排行榜周期">
        <button
          v-for="period in PERIODS"
          :key="period.key"
          type="button"
          role="tab"
          :aria-selected="activePeriod === period.key"
          :class="{ active: activePeriod === period.key }"
          @click="switchPeriod(period.key)"
        >
          {{ period.label }}
        </button>
      </div>
    </header>

    <div v-if="activeState.isLoading" class="state-card" aria-live="polite">
      <span class="state-icon">⏳</span>
      <strong>正在汇总积分…</strong>
    </div>

    <div v-else-if="activeState.loadError" class="state-card error-state" role="alert">
      <span class="state-icon">🌧️</span>
      <strong>排行榜暂时无法读取</strong>
      <span>请检查网络后重试，已有积分不会受到影响。</span>
      <button type="button" @click="retryCurrentPeriod">重新读取</button>
    </div>

    <div v-else-if="activeState.rows.length === 0" class="state-card">
      <span class="state-icon">🌱</span>
      <strong>这个榜单还没有积分记录</strong>
      <span>{{ emptyDescription }}</span>
    </div>

    <template v-else>
      <ol class="ranking-list" aria-label="积分排名">
        <li
          v-for="(row, index) in visibleRows"
          :key="`${activePeriod}-${currentPage}-${index}-${row.rank}-${row.displayName}`"
          :class="{ 'current-user': row.isCurrentUser }"
        >
          <span class="rank" :class="`rank-${Math.min(row.rank, 4)}`">{{ rankBadge(row.rank) }}</span>
          <div class="player" :class="`level-${row.level}`">
            <strong>{{ row.displayName }}</strong>
            <small class="level-chip">Lv{{ row.level }}</small>
            <span v-if="row.isCurrentUser">这是你</span>
          </div>
          <span class="points">{{ formatPoints(row.points) }} 分</span>
        </li>
      </ol>

      <nav v-if="totalPages > 1" class="pager" aria-label="积分排行榜分页">
        <button type="button" :disabled="currentPage === 1" @click="currentPage--">上一页</button>
        <span>第 {{ currentPage }} / {{ totalPages }} 页</span>
        <button type="button" :disabled="currentPage === totalPages" @click="currentPage++">下一页</button>
      </nav>
    </template>
  </section>
</template>

<style scoped>
.leaderboard { animation: fadeIn 0.4s ease; }
.leaderboard-header { display: flex; align-items: flex-end; justify-content: space-between; gap: 18px; margin-bottom: 16px; }
.eyebrow { margin: 0 0 4px; color: #7c3aed; font-size: 11px; font-weight: 900; letter-spacing: 0.12em; }
h2 { margin: 0; color: #1e293b; font-size: 24px; font-weight: 900; }
.description { margin: 6px 0 0; color: #64748b; font-size: 12px; font-weight: 600; }
.period-tabs { display: flex; gap: 6px; padding: 4px; border-radius: 12px; background: #f5f3ff; }
.period-tabs button { border: 0; border-radius: 9px; padding: 8px 13px; background: transparent; color: #7c3aed; font-size: 11px; font-weight: 900; cursor: pointer; }
.period-tabs button.active { background: white; box-shadow: 0 3px 10px rgba(124, 58, 237, 0.12); color: #5b21b6; }
.ranking-list { display: flex; flex-direction: column; gap: 8px; margin: 0; padding: 0; list-style: none; }
.ranking-list li { display: grid; grid-template-columns: 42px minmax(0, 1fr) auto; align-items: center; gap: 12px; padding: 13px 15px; border: 1px solid #f1f5f9; border-radius: 14px; background: rgba(255, 255, 255, 0.92); }
.ranking-list li.current-user { border-color: #c4b5fd; background: #f5f3ff; box-shadow: 0 4px 14px rgba(124, 58, 237, 0.08); }
.rank { display: grid; width: 34px; height: 34px; place-items: center; border-radius: 50%; background: #f1f5f9; color: #64748b; font-size: 12px; font-weight: 900; }
.rank-1, .rank-2, .rank-3 { background: #fff7ed; font-size: 20px; }
.player { display: flex; min-width: 0; align-items: center; gap: 8px; }
.player strong { overflow: hidden; color: #334155; font-size: 13px; text-overflow: ellipsis; white-space: nowrap; }
.player span { flex: 0 0 auto; padding: 2px 7px; border-radius: 999px; background: #ede9fe; color: #6d28d9; font-size: 9px; font-weight: 900; }
.level-chip { flex: 0 0 auto; padding: 2px 6px; border-radius: 999px; background: #f1f5f9; color: #64748b; font-size: 8px; font-weight: 900; }
.player.level-1 strong { color: #9a3412; }
.player.level-2 strong { color: #475569; text-shadow: 0 0 10px rgba(148,163,184,.28); }
.player.level-3 strong { color: #a16207; text-shadow: 0 0 10px rgba(234,179,8,.24); }
.player.level-4 strong { color: #7e22ce; text-shadow: 0 0 12px rgba(168,85,247,.28); }
.points { color: #7c3aed; font-size: 13px; font-weight: 900; white-space: nowrap; }
.state-card { display: flex; min-height: 190px; flex-direction: column; align-items: center; justify-content: center; gap: 8px; padding: 24px; border: 1px dashed #c4b5fd; border-radius: 18px; background: rgba(255, 255, 255, 0.75); color: #64748b; text-align: center; }
.state-card strong { color: #334155; font-size: 15px; }
.state-card span:not(.state-icon) { font-size: 12px; }
.state-icon { font-size: 28px; }
.state-card button, .pager button { border: 0; border-radius: 10px; background: #7c3aed; color: white; padding: 8px 14px; font-size: 11px; font-weight: 900; cursor: pointer; }
.state-card button { margin-top: 6px; }
.error-state { border-color: #fecdd3; }
.pager { display: flex; align-items: center; justify-content: center; gap: 12px; margin-top: 20px; color: #64748b; font-size: 11px; font-weight: 800; }
.pager button:disabled { cursor: not-allowed; opacity: 0.4; }

@media (max-width: 640px) {
  .leaderboard-header { align-items: stretch; flex-direction: column; }
  .period-tabs { align-self: stretch; }
  .period-tabs button { flex: 1; }
  .ranking-list li { grid-template-columns: 36px minmax(0, 1fr) auto; gap: 9px; padding: 12px; }
  .rank { width: 30px; height: 30px; }
}
</style>
