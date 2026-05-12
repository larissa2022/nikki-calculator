<script setup>
import { ref, computed, watch } from 'vue'

// 1. 接收从 App.vue (父组件) 传过来的数据
const props = defineProps({
  wardrobe: { type: Array, required: true }, // 完整图鉴数据
  ownedIds: { type: Array, required: true }, // 用户拥有的衣服 ID 列表
  stages: { type: Array, required: true }    // 竞技场主题关卡数据
})

const selectedTheme = ref('')

// 🌟 监听：当关卡数据加载完毕时，自动选中第一个主题
watch(() => props.stages, (newStages) => {
  if (newStages.length > 0 && !selectedTheme.value) {
    selectedTheme.value = newStages[0].name
  }
}, { immediate: true })

// ====== 🌟 新增：一键复制功能 ======
const copiedId = ref(null) // 用于记录当前哪个部件显示“✅”

const copyName = async (item) => {
  try {
    // 调用现代浏览器原生剪贴板 API
    await navigator.clipboard.writeText(item.name)
    // 视觉反馈：将状态设为该衣服的 ID
    copiedId.value = item.id
    // 1.5 秒后恢复原来的复制图标
    setTimeout(() => {
      if (copiedId.value === item.id) copiedId.value = null
    }, 1500)
  } catch (err) {
    alert('复制失败，可能是浏览器权限限制~')
  }
}

// 2. 🌟 终极搭配计算引擎
const outfitResult = computed(() => {
  if (props.wardrobe.length === 0 || props.stages.length === 0) {
    return { items: [], totalScore: 0, penaltyRate: 100, accCount: 0 }
  }

  const currentStage = props.stages.find(s => s.name === selectedTheme.value)
  if (!currentStage || !currentStage.weights) return { items: [], totalScore: 0, penaltyRate: 100, accCount: 0 }
  
  const themeWeights = currentStage.weights

  // 算法优化：将数组转为 Set，底层使用哈希映射，实现 O(1) 极速查找
  const wardrobeSet = new Set(props.ownedIds)
  const availableClothes = wardrobeSet.size > 0 
    ? props.wardrobe.filter(c => wardrobeSet.has(c.id))
    : props.wardrobe

  // 计算每件衣服的加权分数
  const scoredClothes = availableClothes.map(clothes => {
    let score = 0
    const s = clothes.scores || {}
    score += (s.simple || 0) * (themeWeights.simple || 0)
    score += (s.gorgeous || 0) * (themeWeights.gorgeous || 0)
    score += (s.cute || 0) * (themeWeights.cute || 0)
    score += (s.mature || 0) * (themeWeights.mature || 0)
    score += (s.active || 0) * (themeWeights.active || 0)
    score += (s.elegant || 0) * (themeWeights.elegant || 0)
    score += (s.pure || 0) * (themeWeights.pure || 0)
    score += (s.sexy || 0) * (themeWeights.sexy || 0)
    score += (s.cool || 0) * (themeWeights.cool || 0)
    score += (s.warm || 0) * (themeWeights.warm || 0)
    return { ...clothes, finalScore: Math.round(score) }
  })

  // 选出每个部位的最高分
  const bestPerCategory = new Map()
  scoredClothes.forEach(item => {
    const existing = bestPerCategory.get(item.category)
    if (!existing || existing.finalScore < item.finalScore) {
      bestPerCategory.set(item.category, item)
    }
  })

  // 处理连衣裙 vs 上下装互斥逻辑
  const dress = bestPerCategory.get('连衣裙')
  const top = bestPerCategory.get('上衣') || bestPerCategory.get('上装') 
  const bottom = bestPerCategory.get('下装')
  const dressScore = dress ? dress.finalScore : 0
  const topBottomScore = (top ? top.finalScore : 0) + (bottom ? bottom.finalScore : 0)

  if (dressScore > topBottomScore) {
    if (top) bestPerCategory.delete(top.category)
    if (bottom) bestPerCategory.delete(bottom.category)
  } else {
    if (dress) bestPerCategory.delete('连衣裙')
  }

  // 饰品惩罚逻辑分离
  const baseItems = []
  const accItems = []
  bestPerCategory.forEach(item => {
    if (item.category.includes('饰品')) accItems.push(item)
    else baseItems.push(item)
  })

  accItems.sort((a, b) => b.finalScore - a.finalScore)
  const selectedAccs = []
  let maxAccTotal = 0
  let currentPenalty = 1.0

  for (let i = 0; i < accItems.length; i++) {
    const item = accItems[i]
    const nextCount = selectedAccs.length + 1
    const nextPenalty = nextCount <= 3 ? 1.0 : Math.max(0.2, 1.0 - (nextCount - 3) * 0.05)
    const sumWithoutPenalty = selectedAccs.reduce((sum, a) => sum + a.finalScore, 0) + item.finalScore
    const nextAccTotal = sumWithoutPenalty * nextPenalty

    if (nextAccTotal > maxAccTotal || nextCount <= 3) {
      selectedAccs.push({ ...item, isAcc: true })
      maxAccTotal = nextAccTotal
      currentPenalty = nextPenalty
    } else { break }
  }

  baseItems.sort((a, b) => b.finalScore - a.finalScore)
  return {
    items: [...baseItems, ...selectedAccs],
    totalScore: Math.round(baseItems.reduce((sum, item) => sum + item.finalScore, 0) + maxAccTotal),
    penaltyRate: Math.round(currentPenalty * 100),
    accCount: selectedAccs.length
  }
})
</script>

<template>
  <div class="calculator-module">
    <div class="control-panel">
      <label>选择竞技场主题：</label>
      <select v-model="selectedTheme">
        <option v-for="stage in stages" :key="stage.id" :value="stage.name">
          {{ stage.name }}
        </option>
      </select>
    </div>

    <div class="result-panel">
      <div class="score-board">
        <div class="score-item">
          <span class="label">预计极限总分</span>
          <span class="huge-score">{{ outfitResult.totalScore }}</span>
        </div>
        <div class="score-item acc-info">
          <span class="label">佩戴饰品数 / 系数</span>
          <span class="value">{{ outfitResult.accCount }}件 / {{ outfitResult.penaltyRate }}%</span>
        </div>
      </div>
      
      <div class="item-list">
        <div class="item-card" v-for="item in outfitResult.items" :key="item.id">
          <div class="item-category" :class="{'is-acc': item.isAcc}">{{ item.category }}</div>
          <div class="item-info">
            
            <div class="name-group">
              <span class="item-name" @click="copyName(item)" title="点击复制">{{ item.name }}</span>
              <button class="btn-copy" @click="copyName(item)" :title="'复制 ' + item.name">
                <span v-if="copiedId === item.id" class="icon-success">✅</span>
                <span v-else class="icon-copy">📋</span>
              </button>
            </div>

            <span class="item-score">{{ item.finalScore }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ==========================================
   🧮 1. 计算器专属容器与排版
   ========================================== */
.calculator-module { animation: fadeIn 0.4s ease; }
.control-panel, .result-panel { background: #fff; padding: 25px; border-radius: 16px; box-shadow: 0 10px 25px rgba(124,58,237,0.05); margin-bottom: 25px; border: 1px solid #f3f4f6; }

/* ==========================================
   🏆 2. 顶部分数看板
   ========================================== */
.score-board { display: flex; justify-content: space-between; align-items: center; background: #fdf2f8; padding: 15px 20px; border-radius: 12px; margin-bottom: 20px; border-left: 5px solid #f472b6;}
.score-item { display: flex; flex-direction: column; }
.acc-info { align-items: flex-end; font-size: 14px;}
.label { color: #6b7280; margin-bottom: 5px; font-size: 12px; text-transform: uppercase; font-weight: bold;}
.huge-score { font-size: 28px; font-weight: 900; color: #db2777; }
.value { font-weight: 900; color: #374151;}

/* ==========================================
   👗 3. 搭配推荐列表与卡片
   ========================================== */
.item-list { display: flex; flex-direction: column; gap: 8px; }
.item-card { display: flex; justify-content: space-between; align-items: center; padding: 12px 15px; background: #f8fafc; border-radius: 10px; border: 1px solid #f1f5f9;}
.item-category { color: #64748b; font-weight: 800; font-size: 13px; width: 70px;}
.item-category.is-acc { color: #8b5cf6; } 

.item-info { flex-grow: 1; display: flex; justify-content: space-between; align-items: center; }
.item-score { color: #f472b6; font-weight: 900; font-family: monospace; font-size: 15px;}

/* ==========================================
   📋 4. 一键复制功能特调
   ========================================== */
.name-group { display: flex; align-items: center; gap: 6px; }
.item-name { font-weight: 900; color: #1e293b; cursor: pointer; transition: color 0.2s; font-size: 14px;}
.item-name:hover { color: #f472b6; text-decoration: underline; }

.btn-copy { background: none; border: none; cursor: pointer; padding: 4px; display: flex; align-items: center; justify-content: center; border-radius: 6px; transition: all 0.2s; }
.icon-copy { filter: grayscale(1); opacity: 0.4; font-size: 14px; transition: all 0.2s; }
.btn-copy:hover { background: #f1f5f9; }
.btn-copy:hover .icon-copy { opacity: 1; transform: scale(1.1); filter: none; }
.icon-success { font-size: 14px; animation: popIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275); }
</style>