<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { supabase } from '../api/supabase'
import {
  buildContributorEntries,
  fetchPublicClothingContributors,
  getContributorPresentation
} from '../api/contributorsService'

const props = defineProps({
  wardrobe: { type: Array, required: true }
})

const PAGE_SIZE = 12
const searchQuery = ref('')
const contributorRows = ref([])
const isLoading = ref(false)
const loadError = ref(false)
const currentPage = ref(1)

const entries = computed(() => buildContributorEntries(contributorRows.value, props.wardrobe))
const filteredEntries = computed(() => {
  const keyword = searchQuery.value.trim().toLocaleLowerCase('zh-CN')
  if (!keyword) return entries.value

  return entries.value.filter(entry => [
    entry.name,
    entry.gameId,
    entry.category,
    ...entry.contributors.map(contributor => contributor.displayName)
  ].some(value => String(value || '').toLocaleLowerCase('zh-CN').includes(keyword)))
})
const totalPages = computed(() => Math.max(1, Math.ceil(filteredEntries.value.length / PAGE_SIZE)))
const visibleEntries = computed(() => {
  const start = (currentPage.value - 1) * PAGE_SIZE
  return filteredEntries.value.slice(start, start + PAGE_SIZE)
})

watch(searchQuery, () => {
  currentPage.value = 1
})
watch(totalPages, nextTotal => {
  if (currentPage.value > nextTotal) currentPage.value = nextTotal
})

const loadContributors = async () => {
  isLoading.value = true
  loadError.value = false

  try {
    contributorRows.value = await fetchPublicClothingContributors(supabase)
  } catch (error) {
    console.error('读取图鉴贡献者失败:', error)
    contributorRows.value = []
    loadError.value = true
  } finally {
    isLoading.value = false
  }
}

const formatDate = (value) => {
  if (!value) return '时间未知'

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '时间未知'

  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(date)
}

onMounted(loadContributors)
</script>

<template>
  <section class="contributor-gallery" aria-labelledby="contributor-gallery-title">
    <div class="gallery-header">
      <div>
        <p class="eyebrow">图鉴共建记录</p>
        <h2 id="contributor-gallery-title">贡献者名录</h2>
        <p class="description">每件服装展示最早参与有效入库的前 3 位贡献者。</p>
      </div>
      <label class="search-box">
        <span class="sr-only">搜索服装或贡献者</span>
        <input v-model="searchQuery" type="search" placeholder="搜索服装、编号或贡献者" />
      </label>
    </div>

    <div v-if="isLoading" class="state-card" aria-live="polite">
      <span class="state-icon">⏳</span>
      <strong>正在读取贡献记录…</strong>
    </div>

    <div v-else-if="loadError" class="state-card error-state" role="alert">
      <span class="state-icon">🌧️</span>
      <strong>贡献者暂时无法读取</strong>
      <span>请检查网络后重试，其他图鉴功能不受影响。</span>
      <button type="button" @click="loadContributors">重新读取</button>
    </div>

    <div v-else-if="filteredEntries.length === 0" class="state-card">
      <span class="state-icon">🌱</span>
      <strong>{{ searchQuery ? '没有找到匹配记录' : '还没有可展示的贡献记录' }}</strong>
      <span>{{ searchQuery ? '换一个名称、编号或贡献者试试。' : '新的有效入库完成后会自动出现在这里。' }}</span>
    </div>

    <template v-else>
      <div class="entry-grid">
        <article v-for="entry in visibleEntries" :key="entry.clothesId" class="entry-card">
          <header class="entry-title">
            <div>
              <span v-if="entry.category" class="category-tag">{{ entry.category }}</span>
              <h3>{{ entry.name }}</h3>
            </div>
            <span v-if="entry.gameId" class="game-id">#{{ entry.gameId }}</span>
          </header>

          <ol class="contributor-list" aria-label="前 3 位贡献者">
            <li
              v-for="contributor in entry.contributors"
              :key="`${entry.clothesId}-${contributor.rank}`"
              :class="[`contributor-level-${contributor.level}`, { 'level-highlight': getContributorPresentation(contributor.level).highlighted }]"
            >
              <span class="rank-badge" :class="`rank-${contributor.rank}`">{{ contributor.rank }}</span>
              <span class="contributor-name">
                {{ contributor.displayName }}
                <small v-if="getContributorPresentation(contributor.level).showSignature" class="signature-badge">Lv{{ contributor.level }} · 贡献者署名</small>
              </span>
              <time :datetime="contributor.contributedAt || undefined">
                {{ formatDate(contributor.contributedAt) }}
              </time>
            </li>
          </ol>
        </article>
      </div>

      <nav v-if="totalPages > 1" class="pager" aria-label="贡献者名录分页">
        <button type="button" :disabled="currentPage === 1" @click="currentPage--">上一页</button>
        <span>第 {{ currentPage }} / {{ totalPages }} 页</span>
        <button type="button" :disabled="currentPage === totalPages" @click="currentPage++">下一页</button>
      </nav>
    </template>
  </section>
</template>

<style scoped>
.contributor-gallery { animation: fadeIn 0.4s ease; }
.gallery-header { display: flex; align-items: flex-end; justify-content: space-between; gap: 18px; margin-bottom: 20px; }
.eyebrow { margin: 0 0 4px; color: #db2777; font-size: 11px; font-weight: 900; letter-spacing: 0.12em; }
h2 { margin: 0; color: #1e293b; font-size: 24px; font-weight: 900; }
.description { margin: 6px 0 0; color: #64748b; font-size: 12px; font-weight: 600; }
.search-box { flex: 0 0 210px; }
.search-box input { width: 100%; padding: 10px 12px; border: 1.5px solid #f1f5f9; border-radius: 12px; background: white; color: #334155; font-size: 12px; font-weight: 700; outline: none; }
.search-box input:focus { border-color: #f472b6; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.12); }
.entry-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
.entry-card { padding: 16px; border: 1px solid #f3e8ff; border-radius: 16px; background: rgba(255, 255, 255, 0.92); box-shadow: 0 5px 15px rgba(124, 58, 237, 0.05); }
.entry-title { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; padding-bottom: 12px; border-bottom: 1px solid #f8fafc; }
.entry-title h3 { margin: 5px 0 0; color: #334155; font-size: 15px; font-weight: 900; overflow-wrap: anywhere; }
.category-tag { display: inline-flex; padding: 2px 7px; border-radius: 999px; background: #fdf2f8; color: #db2777; font-size: 9px; font-weight: 900; }
.game-id { color: #94a3b8; font-family: monospace; font-size: 10px; font-weight: 800; white-space: nowrap; }
.contributor-list { display: flex; flex-direction: column; gap: 9px; margin: 12px 0 0; padding: 0; list-style: none; }
.contributor-list li { display: grid; grid-template-columns: 24px minmax(0, 1fr) auto; align-items: center; gap: 8px; padding: 4px 6px; border-radius: 9px; }
.contributor-list li.level-highlight { border: 1px solid #e9d5ff; background: linear-gradient(90deg, #faf5ff, #fff); }
.rank-badge { display: grid; width: 22px; height: 22px; place-items: center; border-radius: 50%; background: #f1f5f9; color: #64748b; font-size: 10px; font-weight: 900; }
.rank-1 { background: #fef3c7; color: #b45309; }
.rank-2 { background: #f1f5f9; color: #475569; }
.rank-3 { background: #ffedd5; color: #c2410c; }
.contributor-name { color: #475569; font-size: 12px; font-weight: 800; overflow-wrap: anywhere; }
.signature-badge { display: inline-flex; margin-left: 5px; padding: 1px 5px; border-radius: 999px; background: #ffedd5; color: #9a3412; font-size: 8px; font-weight: 900; vertical-align: middle; }
.contributor-level-2 .contributor-name { color: #475569; text-shadow: 0 0 10px rgba(148, 163, 184, 0.25); }
.contributor-level-3 .contributor-name { color: #a16207; text-shadow: 0 0 10px rgba(234, 179, 8, 0.22); }
.contributor-level-4 .contributor-name { color: #7e22ce; text-shadow: 0 0 12px rgba(168, 85, 247, 0.24); }
time { color: #94a3b8; font-size: 9px; font-weight: 700; white-space: nowrap; }
.state-card { display: flex; min-height: 190px; flex-direction: column; align-items: center; justify-content: center; gap: 8px; padding: 24px; border: 1px dashed #f9a8d4; border-radius: 18px; background: rgba(255, 255, 255, 0.75); color: #64748b; text-align: center; }
.state-card strong { color: #334155; font-size: 15px; }
.state-card span:not(.state-icon) { font-size: 12px; }
.state-icon { font-size: 28px; }
.state-card button, .pager button { border: 0; border-radius: 10px; background: #f472b6; color: white; padding: 8px 14px; font-size: 11px; font-weight: 900; cursor: pointer; }
.state-card button { margin-top: 6px; }
.pager { display: flex; align-items: center; justify-content: center; gap: 12px; margin-top: 20px; color: #64748b; font-size: 11px; font-weight: 800; }
.pager button:disabled { cursor: not-allowed; opacity: 0.4; }
.sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
.error-state { border-color: #fecdd3; }

@media (max-width: 640px) {
  .gallery-header { align-items: stretch; flex-direction: column; }
  .search-box { flex-basis: auto; }
  .entry-grid { grid-template-columns: 1fr; }
}
</style>
