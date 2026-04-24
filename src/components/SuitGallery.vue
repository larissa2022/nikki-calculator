<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  wardrobe: { type: Array, required: true }, // 包含所有衣服（需要带有 suit_name 字段）
  ownedIds: { type: Array, required: true },
  isLoggedIn: { type: Boolean, default: false }
})

const emit = defineEmits(['update:ownedIds', 'save-cloud'])

const importText = ref('')
const searchQuery = ref('')

// ====== 🌟 核心引擎：动态聚合出所有套装 ======
const allSuits = computed(() => {
  const suitMap = {}
  
  // 遍历整个大衣柜，把带有 suit_name 的衣服按套装归类
  props.wardrobe.forEach(item => {
    const sName = item.suit_name?.trim()
    if (sName) {
      if (!suitMap[sName]) suitMap[sName] = []
      suitMap[sName].push(item.id)
    }
  })

  // 计算每个套装的收集进度
  return Object.keys(suitMap).map(name => {
    const partIds = suitMap[name]
    const ownedCount = partIds.filter(id => props.ownedIds.includes(id)).length
    return {
      name,
      partIds,
      total: partIds.length,
      owned: ownedCount,
      isComplete: ownedCount === partIds.length,
      percent: Math.floor((ownedCount / partIds.length) * 100)
    }
  }).sort((a, b) => {
    // 排序逻辑：未集齐的排前面，同状态按进度降序
    if (a.isComplete === b.isComplete) return b.percent - a.percent
    return a.isComplete ? 1 : -1
  })
})

// ====== 过滤展示的套装 ======
const displayedSuits = computed(() => {
  const query = searchQuery.value.trim()
  if (!query) return allSuits.value
  return allSuits.value.filter(s => s.name.includes(query))
})

// ====== 🚀 批量文本导入套装 ======
const handleSuitImport = () => {
  const inputNames = importText.value.split(/[,，\s\n]+/).map(n => n.trim()).filter(n => n !== '')
  if (inputNames.length === 0) return alert('请输入套装名字哦~')

  let addedCount = 0
  const notFound = []
  const updatedOwnedIds = [...props.ownedIds]

  inputNames.forEach(name => {
    const suit = allSuits.value.find(s => s.name === name)
    if (suit) {
      suit.partIds.forEach(id => {
        if (!updatedOwnedIds.includes(id)) {
          updatedOwnedIds.push(id)
          addedCount++
        }
      })
    } else {
      notFound.push(name)
    }
  })

  if (addedCount > 0) {
    emit('update:ownedIds', updatedOwnedIds)
    if (props.isLoggedIn) emit('save-cloud')
    alert(`✨ 琉璃共鸣！成功录入了 ${addedCount} 个套装部件！`)
  } else {
    alert('没有录入新部件，可能是已经集齐啦。')
  }

  if (notFound.length > 0) {
    alert(`⚠️ 以下套装在图鉴中未找到：\n${notFound.join(', ')}`)
  }
  
  importText.value = ''
}

// ====== 👆 一键点亮单个套装 ======
const unlockSingleSuit = (suit) => {
  const updatedOwnedIds = [...props.ownedIds]
  let addedCount = 0

  suit.partIds.forEach(id => {
    if (!updatedOwnedIds.includes(id)) {
      updatedOwnedIds.push(id)
      addedCount++
    }
  })

  emit('update:ownedIds', updatedOwnedIds)
  if (props.isLoggedIn) emit('save-cloud')
}
</script>

<template>
  <div class="suit-gallery glass-panel">
    
    <div class="batch-import-zone">
      <div class="zone-header">
        <h2>🎁 批量唤醒套装</h2>
        <span class="sub-title">支持一次性输入多个套装名</span>
      </div>
      <div class="import-controls">
        <textarea 
          v-model="importText" 
          rows="2" 
          placeholder="输入套装名字（如：星之海, 韶颜倾城），用逗号或空格隔开..."
        ></textarea>
        <button class="btn-primary" @click="handleSuitImport">一键全部集齐</button>
      </div>
    </div>

    <div class="divider">
      <span class="heart-deco">♥</span>
    </div>

    <div class="visual-gallery-zone">
      <div class="gallery-header">
        <h3>✨ 套装图鉴</h3>
        <input type="text" v-model="searchQuery" class="search-box" placeholder="搜索套装..." />
      </div>

      <div class="suit-grid" v-if="displayedSuits.length > 0">
        <div 
          v-for="suit in displayedSuits" 
          :key="suit.name" 
          class="suit-card" 
          :class="{ 'is-complete': suit.isComplete }"
        >
          <div class="card-top">
            <span class="suit-name">{{ suit.name }}</span>
            <span class="suit-badge" v-if="suit.isComplete">已集齐</span>
          </div>
          
          <div class="progress-section">
            <div class="progress-info">
              <span class="percent-num">{{ suit.percent }}%</span>
              <span class="count-num">{{ suit.owned }}/{{ suit.total }}</span>
            </div>
            <div class="progress-track">
              <div class="progress-fill" :style="{ width: suit.percent + '%' }"></div>
            </div>
          </div>

          <button 
            class="btn-unlock" 
            v-if="!suit.isComplete" 
            @click="unlockSingleSuit(suit)"
          >
            一键补齐部件
          </button>
        </div>
      </div>
      
      <div v-else class="empty-state">
        <p>图鉴里还没有录入这个套装哦~</p>
      </div>
    </div>

  </div>
</template>

<style scoped>
.glass-panel {
  background: rgba(255, 255, 255, 0.85); border: 1px solid rgba(255, 255, 255, 0.4);
  padding: 25px; border-radius: 20px; box-shadow: 0 10px 30px rgba(244, 114, 182, 0.08);
  animation: fadeIn 0.4s ease;
}

/* 批量导入区 */
.zone-header { margin-bottom: 12px; }
.zone-header h2 { margin: 0; color: #db2777; font-size: 18px; font-weight: 900; }
.sub-title { font-size: 11px; color: #94a3b8; font-weight: bold; }

.import-controls { display: flex; flex-direction: column; gap: 10px; }
textarea {
  width: 100%; padding: 12px; border: 1.5px solid #f1f5f9; border-radius: 14px;
  background: rgba(255,255,255,0.6); outline: none; resize: vertical; font-size: 13px;
  transition: all 0.3s; box-sizing: border-box;
}
textarea:focus { border-color: #f472b6; background: #fff; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }
.btn-primary {
  background: linear-gradient(135deg, #a855f7 0%, #d946ef 100%); color: white; border: none;
  padding: 12px; border-radius: 14px; font-weight: bold; cursor: pointer; transition: all 0.2s;
  box-shadow: 0 4px 15px rgba(217, 70, 239, 0.2);
}
.btn-primary:hover { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(217, 70, 239, 0.3); }

/* 华丽分割线 */
.divider {
  display: flex; align-items: center; justify-content: center; margin: 25px 0;
  position: relative;
}
.divider::before, .divider::after { content: ''; flex: 1; height: 1.5px; background: #fbcfe8; }
.heart-deco { margin: 0 15px; color: #f472b6; font-size: 14px; }

/* 可视化图鉴区 */
.gallery-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
.gallery-header h3 { margin: 0; color: #9333ea; font-size: 16px; font-weight: 900; }
.search-box {
  padding: 6px 15px; border: 1.5px solid #e9d5ff; border-radius: 20px; font-size: 12px;
  outline: none; width: 140px; background: #faf5ff; transition: all 0.3s;
}
.search-box:focus { border-color: #c084fc; width: 180px; background: #fff; }

.suit-grid {
  display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 15px;
}

/* 套装卡片 */
.suit-card {
  background: white; border: 1.5px solid #f3e8ff; border-radius: 16px; padding: 15px;
  display: flex; flex-direction: column; gap: 12px; transition: all 0.2s;
  box-shadow: 0 4px 12px rgba(0,0,0,0.02);
}
.suit-card:hover { transform: translateY(-3px); border-color: #d8b4fe; box-shadow: 0 8px 20px rgba(168, 85, 247, 0.1); }
.suit-card.is-complete { background: #fdf2f8; border-color: #fbcfe8; }

.card-top { display: flex; justify-content: space-between; align-items: flex-start; }
.suit-name { font-size: 15px; font-weight: 900; color: #475569; }
.suit-badge { background: #f472b6; color: white; font-size: 10px; font-weight: bold; padding: 2px 6px; border-radius: 8px; }

.progress-section { display: flex; flex-direction: column; gap: 6px; }
.progress-info { display: flex; justify-content: space-between; align-items: center; }
.percent-num { font-size: 14px; font-weight: 900; color: #a855f7; }
.count-num { font-size: 11px; color: #94a3b8; font-family: monospace; font-weight: bold; }

.progress-track { height: 8px; background: #f1f5f9; border-radius: 10px; overflow: hidden; }
.progress-fill { height: 100%; background: linear-gradient(90deg, #c084fc 0%, #d946ef 100%); border-radius: 10px; transition: width 0.5s ease; }
.is-complete .progress-fill { background: linear-gradient(90deg, #fbcfe8 0%, #f472b6 100%); }

.btn-unlock {
  background: #fff; border: 1.5px solid #d8b4fe; color: #9333ea; font-size: 12px; font-weight: bold;
  padding: 8px; border-radius: 10px; cursor: pointer; transition: all 0.2s; margin-top: auto;
}
.btn-unlock:hover { background: #9333ea; color: white; }

.empty-state { text-align: center; color: #94a3b8; font-size: 13px; padding: 30px 0; }

@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
</style>