<script setup>
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../api/supabase'
import { fetchHomepageThanks } from '../api/homepageThanksService'

const rows = ref([])

const monthLabel = computed(() => {
  const [year, month] = String(rows.value[0]?.monthStart || '').split('-')
  return year && month ? `${year} 年 ${Number(month)} 月` : ''
})
const accessibleNames = computed(() => rows.value.map(row => row.displayName).join('、'))
const marqueeRows = computed(() => (
  rows.value.length > 1 ? [...rows.value, ...rows.value] : rows.value
))
const animationDuration = computed(() => `${Math.max(18, rows.value.length * 3)}s`)

onMounted(async () => {
  try {
    rows.value = await fetchHomepageThanks(supabase)
  } catch (error) {
    console.error('读取首页月度鸣谢失败:', error)
    rows.value = []
  }
})
</script>

<template>
  <aside
    v-if="rows.length"
    class="monthly-thanks"
    aria-labelledby="monthly-thanks-title"
  >
    <div class="monthly-thanks__heading">
      <span aria-hidden="true">💖</span>
      <div>
        <p class="monthly-thanks__eyebrow">{{ monthLabel }}活跃玩家</p>
        <h2 id="monthly-thanks-title">感谢你们让图鉴更完整</h2>
      </div>
    </div>

    <p class="sr-only">本月鸣谢：{{ accessibleNames }}</p>
    <div class="monthly-thanks__viewport" aria-hidden="true">
      <div
        class="monthly-thanks__track"
        :class="{ 'monthly-thanks__track--moving': rows.length > 1 }"
        :style="{ '--thanks-duration': animationDuration }"
      >
        <span
          v-for="(row, index) in marqueeRows"
          :key="`${row.displayOrder}-${index}`"
          class="monthly-thanks__name"
          :class="{ 'monthly-thanks__name--duplicate': index >= rows.length }"
        >
          <span class="monthly-thanks__spark">✦</span>
          {{ row.displayName }}
        </span>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.monthly-thanks {
  display: grid;
  grid-template-columns: minmax(180px, auto) minmax(0, 1fr);
  align-items: center;
  gap: 18px;
  margin-bottom: 18px;
  padding: 14px 18px;
  overflow: hidden;
  border: 1px solid #fbcfe8;
  border-radius: 18px;
  background: linear-gradient(120deg, #fff7fb 0%, #fdf4ff 55%, #faf5ff 100%);
  box-shadow: 0 8px 24px rgba(219, 39, 119, 0.08);
}
.monthly-thanks__heading { display: flex; align-items: center; gap: 10px; color: #9d174d; }
.monthly-thanks__heading > span { font-size: 24px; }
.monthly-thanks__eyebrow { margin: 0 0 2px; color: #c026d3; font-size: 10px; font-weight: 900; letter-spacing: 0.08em; }
.monthly-thanks h2 { margin: 0; font-size: 14px; font-weight: 900; white-space: nowrap; }
.monthly-thanks__viewport {
  min-width: 0;
  overflow: hidden;
  -webkit-mask-image: linear-gradient(90deg, transparent, #000 8%, #000 92%, transparent);
  mask-image: linear-gradient(90deg, transparent, #000 8%, #000 92%, transparent);
}
.monthly-thanks__track { display: flex; width: max-content; gap: 24px; padding: 6px 12px; }
.monthly-thanks__track--moving { animation: thanks-scroll var(--thanks-duration) linear infinite; }
.monthly-thanks__name { color: #7e22ce; font-size: 13px; font-weight: 900; white-space: nowrap; }
.monthly-thanks__spark { margin-right: 4px; color: #f472b6; }
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}
@keyframes thanks-scroll { to { transform: translateX(calc(-50% - 12px)); } }
@media (prefers-reduced-motion: reduce) {
  .monthly-thanks__track--moving { width: auto; flex-wrap: wrap; animation: none; }
  .monthly-thanks__viewport { -webkit-mask-image: none; mask-image: none; }
  .monthly-thanks__name--duplicate { display: none; }
}
@media (max-width: 680px) {
  .monthly-thanks { grid-template-columns: 1fr; gap: 8px; }
  .monthly-thanks h2 { white-space: normal; }
}
</style>
