<script setup>
import { computed } from 'vue'
import { USER_LEVELS, getUserRankAndPrivilege } from '../composables/useUserPrivilege'

const props = defineProps({
  totalPoints: { type: Number, required: true }
})

const levelMilestones = USER_LEVELS.filter(level => level.level > 0)
const currentRank = computed(() => getUserRankAndPrivilege(props.totalPoints))
const progressStyle = computed(() => ({ width: `${currentRank.value.progressPercent}%` }))
const formatPoints = (points) => new Intl.NumberFormat('zh-CN').format(points)
const getLevelState = (level) => {
  if (currentRank.value.level < level.level) return 'locked'
  if (currentRank.value.level === level.level) return 'current'
  return 'unlocked'
}
</script>

<template>
  <section class="level-growth" aria-labelledby="level-growth-title">
    <div class="level-growth-summary">
      <div class="level-badge" :class="`level-${currentRank.level}`" aria-hidden="true">
        <span>{{ currentRank.badgeIcon }}</span>
        <small>Lv{{ currentRank.level }}</small>
      </div>
      <div class="level-growth-copy">
        <p class="level-kicker">当前成长等级</p>
        <h4 id="level-growth-title">{{ currentRank.title }}</h4>
        <p>{{ currentRank.badgeName }}</p>
      </div>
      <div class="level-next-copy">
        <template v-if="currentRank.isMaxLevel">
          <strong>已达到最高等级</strong>
          <span>继续贡献仍会正常累计积分</span>
        </template>
        <template v-else>
          <strong>距离 {{ currentRank.nextTitle }} 还差 {{ formatPoints(currentRank.pointsToNext) }} 分</strong>
          <span>下一等级门槛：{{ formatPoints(currentRank.nextThreshold) }} 分</span>
        </template>
      </div>
    </div>

    <div
      class="level-progress-track"
      role="progressbar"
      aria-label="当前等级升级进度"
      aria-valuemin="0"
      aria-valuemax="100"
      :aria-valuenow="currentRank.progressPercent"
    >
      <span :style="progressStyle"></span>
    </div>
    <div class="level-progress-labels">
      <span>{{ formatPoints(currentRank.totalPoints) }} 分</span>
      <span>{{ currentRank.isMaxLevel ? '最高等级' : `${currentRank.progressPercent}%` }}</span>
    </div>

    <ul class="level-milestones" aria-label="等级徽章里程碑">
      <li
        v-for="level in levelMilestones"
        :key="level.level"
        class="level-milestone"
        :class="getLevelState(level)"
      >
        <div class="milestone-icon" :class="`level-${level.level}`" aria-hidden="true">
          {{ level.badgeIcon }}
        </div>
        <div>
          <strong>Lv{{ level.level }} · {{ level.title }}</strong>
          <span>{{ level.badgeName }}</span>
        </div>
        <small v-if="getLevelState(level) === 'current'">当前等级</small>
        <small v-else-if="getLevelState(level) === 'unlocked'">已解锁</small>
        <small v-else>{{ formatPoints(level.threshold) }} 分解锁</small>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.level-growth { margin-top: 22px; padding: 18px; border: 1px solid #ede9fe; border-radius: 18px; background: linear-gradient(135deg, #faf5ff 0%, #fff7ed 100%); }
.level-growth-summary { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; align-items: center; gap: 14px; }
.level-badge { display: grid; width: 66px; height: 66px; place-items: center; border: 2px solid rgba(255, 255, 255, 0.85); border-radius: 20px; box-shadow: 0 8px 22px rgba(124, 58, 237, 0.12); }
.level-badge span { font-size: 26px; line-height: 1; }
.level-badge small { margin-top: -10px; font-size: 10px; font-weight: 900; }
.level-growth-copy, .level-next-copy { min-width: 0; }
.level-kicker { margin: 0 0 2px; color: #8b5cf6; font-size: 10px; font-weight: 900; letter-spacing: 0.08em; }
.level-growth-copy h4 { margin: 0; color: #312e81; font-size: 18px; font-weight: 900; }
.level-growth-copy p:last-child { margin: 2px 0 0; color: #6b7280; font-size: 11px; font-weight: 700; }
.level-next-copy { display: flex; align-items: flex-end; flex-direction: column; text-align: right; }
.level-next-copy strong { color: #6d28d9; font-size: 12px; font-weight: 900; }
.level-next-copy span { margin-top: 3px; color: #64748b; font-size: 10px; font-weight: 700; }
.level-progress-track { height: 9px; margin-top: 16px; overflow: hidden; border-radius: 999px; background: rgba(203, 213, 225, 0.7); }
.level-progress-track span { display: block; height: 100%; border-radius: inherit; background: linear-gradient(90deg, #c084fc, #f472b6, #fb923c); transition: width 0.35s ease; }
.level-progress-labels { display: flex; justify-content: space-between; margin-top: 5px; color: #64748b; font-size: 10px; font-weight: 800; }
.level-milestones { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px; margin: 16px 0 0; padding: 0; list-style: none; }
.level-milestone { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 8px; align-items: center; min-width: 0; padding: 10px; border: 1px solid #e2e8f0; border-radius: 12px; background: rgba(255, 255, 255, 0.82); }
.level-milestone > div:nth-child(2) { min-width: 0; }
.level-milestone strong, .level-milestone span, .level-milestone small { display: block; }
.level-milestone strong { overflow: hidden; color: #334155; font-size: 10px; font-weight: 900; text-overflow: ellipsis; white-space: nowrap; }
.level-milestone span { margin-top: 2px; overflow: hidden; color: #475569; font-size: 9px; font-weight: 700; text-overflow: ellipsis; white-space: nowrap; }
.level-milestone small { grid-column: 1 / -1; color: #7c3aed; font-size: 9px; font-weight: 900; }
.level-milestone.locked { filter: grayscale(0.7); opacity: 0.72; }
.level-milestone.current { border-color: #c084fc; background: #faf5ff; box-shadow: 0 5px 14px rgba(147, 51, 234, 0.08); }
.milestone-icon { display: grid; width: 31px; height: 31px; place-items: center; border-radius: 10px; font-size: 16px; }
.level-0 { background: linear-gradient(135deg, #e2e8f0, #f8fafc); color: #475569; }
.level-1 { background: linear-gradient(135deg, #fed7aa, #fdba74); color: #9a3412; }
.level-2 { background: linear-gradient(135deg, #e2e8f0, #cbd5e1); color: #334155; }
.level-3 { background: linear-gradient(135deg, #fef3c7, #fbbf24); color: #92400e; }
.level-4 { background: linear-gradient(135deg, #ede9fe, #d8b4fe); color: #6b21a8; }

@media (max-width: 760px) {
  .level-growth-summary { grid-template-columns: auto minmax(0, 1fr); }
  .level-next-copy { grid-column: 1 / -1; align-items: flex-start; text-align: left; }
  .level-milestones { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}

@media (max-width: 480px) {
  .level-milestones { grid-template-columns: 1fr; }
  .level-milestone { grid-template-columns: auto minmax(0, 1fr) auto; }
  .level-milestone strong, .level-milestone span { overflow: visible; text-overflow: clip; white-space: normal; }
  .level-milestone small { grid-column: auto; white-space: nowrap; }
}
</style>
