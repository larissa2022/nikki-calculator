<script setup>
import { ref, computed, watch } from 'vue'

const props = defineProps({
  wardrobe: { type: Array, required: true },
  ownedIds: { type: Array, required: true },
  isLoggedIn: { type: Boolean, default: false }
})

const emit = defineEmits(['update:ownedIds', 'save-cloud'])

// ====== 基础状态 ======
const searchQuery = ref('')
const isSelectMode = ref(false)
const selectedIds = ref([])
const activeCategory = ref('全部')
const categories = ['全部', '发型', '连衣裙', '外套', '上装', '下装', '袜子', '鞋子', '饰品', '妆容', '萤光之灵']

const currentPage = ref(1)
const pageSize = ref(40)

// ====== 🌟 核心：收集进度计算 (用于顶部展示) ======
// ====== 🌟 核心：收集进度计算 (用于顶部展示) ======
const collectionStats = computed(() => {
  const ownedSet = new Set(props.ownedIds)
  
  // 计算当前分类的 总数 和 已拥有数
  let totalInCat = 0
  let ownedInCat = 0
  
  props.wardrobe.forEach(item => {
    // 🌟 核心修复：从 === 改为 includes，让统计系统也能识别二、三级精细分类
    const isTargetCat = activeCategory.value === '全部' || (item.category && item.category.includes(activeCategory.value))
    
    if (isTargetCat) {
      totalInCat++
      if (ownedSet.has(item.id)) ownedInCat++
    }
  })

  const percent = totalInCat > 0 ? Math.floor((ownedInCat / totalInCat) * 100) : 0
  return { owned: ownedInCat, total: totalInCat, percent }
})

// ====== 排序与过滤逻辑 ======
// 在 src/components/WardrobeGrid.vue 的 computed 筛选逻辑中修改：

// ====== 排序与过滤逻辑 ======
const filteredClothes = computed(() => {
  const ownedSet = new Set(props.ownedIds);
  const searchStr = searchQuery.value.trim().toLowerCase();
  
  // 1. 过滤逻辑
  const result = props.wardrobe.filter(c => {
    // 必须是已拥有的部件
    if (!ownedSet.has(c.id)) return false;

    // 分类模糊匹配（支持把 饰品-头饰-发饰 归入 饰品）
    if (activeCategory.value !== '全部' && (!c.category || !c.category.includes(activeCategory.value))) return false;

    // 搜索词匹配（名字或编号）
    if (searchStr && !(
      c.name.toLowerCase().includes(searchStr) || 
      (c.game_id && c.game_id.toLowerCase().includes(searchStr))
    )) return false;

    return true;
  });

  // 2. 🌟 恢复灵魂排序：按 game_id 数字大小升序排列
  return result.sort((a, b) => {
    const getVal = (id) => {
      if (!id || id === 'N') return 999999;
      const m = id.match(/\d+/);
      return m ? parseInt(m[0], 10) : 999999;
    };
    return getVal(a.game_id) - getVal(b.game_id);
  });
});

watch([activeCategory, searchQuery], () => {
  currentPage.value = 1
  selectedIds.value = []
})

const totalPages = computed(() => Math.max(1, Math.ceil(filteredClothes.value.length / pageSize.value)))
const paginatedClothes = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return filteredClothes.value.slice(start, start + pageSize.value)
})

const confirmRemove = (item) => {
  if (confirm(`确定要移除【${item.name}】吗？`)) {
    const updated = props.ownedIds.filter(id => id !== item.id)
    emit('update:ownedIds', updated)
    if (props.isLoggedIn) emit('save-cloud')
  }
}

const batchDelete = () => {
  if (selectedIds.value.length === 0) return
  if (confirm(`确认移除选中的 ${selectedIds.value.length} 件服装？`)) {
    const updated = props.ownedIds.filter(id => !selectedIds.value.includes(id))
    emit('update:ownedIds', updated)
    selectedIds.value = []
    isSelectMode.value = false
    if (props.isLoggedIn) emit('save-cloud')
  }
}
</script>

<template>
  <div class="wardrobe-gallery">
    <div class="collection-header">
      <div class="stat-card">
        <div class="stat-info">
          <span class="stat-label">{{ activeCategory === '全部' ? '总收集' : activeCategory }}</span>
          <span class="stat-value">{{ collectionStats.owned }}/{{ collectionStats.total }}</span>
        </div>
        <div class="progress-container">
          <div class="progress-bar" :style="{ width: collectionStats.percent + '%' }"></div>
          <span class="percent-tag">{{ collectionStats.percent }}%</span>
        </div>
      </div>
      
      <div class="header-tools">
        <div class="mini-search">
          <input type="text" v-model="searchQuery" placeholder="搜索..." />
        </div>
        <button class="btn-manage-icon" @click="isSelectMode = !isSelectMode" :class="{ active: isSelectMode }">
          {{ isSelectMode ? '✓' : '⚙' }}
        </button>
      </div>
    </div>

    <div class="category-strip">
      <button 
        v-for="cat in categories" 
        :key="cat"
        class="nav-pill"
        :class="{ active: activeCategory === cat }"
        @click="activeCategory = cat"
      >
        {{ cat }}
      </button>
    </div>
    
    <div class="grid-wrapper" v-if="paginatedClothes.length > 0">
      <div 
        v-for="item in paginatedClothes" 
        :key="item.id" 
        class="cloth-capsule" 
        :class="{ 'is-selected': selectedIds.includes(item.id), 'is-manage': isSelectMode }"
        @click="isSelectMode ? (selectedIds.includes(item.id) ? selectedIds.splice(selectedIds.indexOf(item.id), 1) : selectedIds.push(item.id)) : null"
      >
        <div class="inner-box">
          <div class="box-top">
            <span class="game-id">#{{ item.game_id && item.game_id !== 'N' ? item.game_id : '---' }}</span>
            <button v-if="!isSelectMode" class="btn-close-x" @click.stop="confirmRemove(item)">×</button>
            <div v-else class="check-dot" :class="{ checked: selectedIds.includes(item.id) }"></div>
          </div>

          <div class="box-center">
            <span class="name-text">{{ item.name }}</span>
          </div>

          <div class="box-bottom-deco">
             <div class="line"></div>
             <div class="heart">♥</div>
             <div class="line"></div>
          </div>
        </div>
      </div>
    </div>

    <div v-else class="empty-holder">
      <p>还没有收集到这个分类的部件哦~</p>
    </div>

    <div class="simple-pager" v-if="totalPages > 1">
      <button :disabled="currentPage === 1" @click="currentPage--">‹</button>
      <span>{{ currentPage }} / {{ totalPages }}</span>
      <button :disabled="currentPage === totalPages" @click="currentPage++">›</button>
      <button v-if="isSelectMode" @click="batchDelete" class="btn-batch-del" :disabled="selectedIds.length === 0">批量删除</button>
    </div>
  </div>
</template>

<style scoped>
/* ==========================================
   👗 1. 核心容器与顶部统计面板
   ========================================== */
.wardrobe-gallery { animation: fadeIn 0.4s ease; }

.collection-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }
.stat-card { background: white; border-radius: 12px; padding: 8px 15px; border: 1.5px solid #f3e8ff; flex-grow: 1; max-width: 200px; }
.stat-info { display: flex; justify-content: space-between; margin-bottom: 4px; }
.stat-label { font-size: 11px; color: #db2777; font-weight: 900; }
.stat-value { font-size: 11px; color: #64748b; font-family: monospace; font-weight: bold; }

.progress-container { height: 12px; background: #fdf2f8; border-radius: 10px; position: relative; overflow: hidden; border: 1px solid #fbcfe8; }
.progress-bar { height: 100%; background: linear-gradient(90deg, #fbcfe8 0%, #f472b6 100%); transition: width 0.5s ease; }
.percent-tag { position: absolute; right: 6px; top: 50%; transform: translateY(-50%); font-size: 8px; color: #fff; font-weight: 900; text-shadow: 0 1px 2px rgba(0,0,0,0.1); }

/* ==========================================
   🛠️ 2. 工具栏与纯净导航条
   ========================================== */
.header-tools { display: flex; gap: 8px; align-items: center; margin-left: 15px;}
.mini-search input { border: 1.5px solid #f1f5f9; border-radius: 10px; padding: 4px 10px; font-size: 10px; width: 60px; outline: none; transition: width 0.3s; }
.mini-search input:focus { width: 100px; border-color: #f472b6; }
.btn-manage-icon { background: white; border: 1.5px solid #e2e8f0; color: #94a3b8; width: 28px; height: 28px; border-radius: 50%; cursor: pointer; font-size: 14px; font-weight: bold;}
.btn-manage-icon.active { color: #f472b6; border-color: #f472b6; background: #fff5f8; }

.category-strip { display: flex; gap: 5px; overflow-x: auto; padding-bottom: 10px; margin-bottom: 15px; scrollbar-width: none; border-bottom: 1px solid rgba(244, 114, 182, 0.1); }
.category-strip::-webkit-scrollbar { display: none; }
.nav-pill { white-space: nowrap; background: rgba(255,255,255,0.7); border: 1px solid #f1f5f9; padding: 4px 12px; border-radius: 20px; font-size: 11px; color: #64748b; font-weight: bold; cursor: pointer; transition: all 0.2s; }
.nav-pill.active { background: #f472b6; border-color: #f472b6; color: white; box-shadow: 0 3px 8px rgba(244, 114, 182, 0.2); }

/* ==========================================
   🎴 3. 紧凑型胶囊卡片网格
   ========================================== */
.grid-wrapper { display: grid; grid-template-columns: repeat(auto-fill, minmax(90px, 1fr)); gap: 8px; }
.cloth-capsule { cursor: pointer; transition: transform 0.2s; }
.inner-box { background: rgba(255, 255, 255, 0.9); border: 1.5px solid #f3e8ff; border-radius: 16px; padding: 5px 8px; height: 58px; display: flex; flex-direction: column; justify-content: space-between; box-shadow: 0 2px 5px rgba(0,0,0,0.02); }
.is-selected .inner-box { border-color: #f472b6; background: #fff5f8; }

.box-top { display: flex; justify-content: space-between; align-items: center; }
.game-id { font-size: 9px; color: #94a3b8; font-family: monospace; font-weight: bold; }
.btn-close-x { background: none; border: none; color: #cbd5e1; font-size: 14px; padding: 0; cursor: pointer; line-height: 1;}
.check-dot { width: 10px; height: 10px; border: 1px solid #cbd5e1; border-radius: 50%; }
.check-dot.checked { background: #f472b6; border-color: #f472b6; }

.box-center { flex-grow: 1; display: flex; align-items: center; justify-content: center; margin: 1px 0; }
.name-text { font-size: 13px; font-weight: 800; color: #334155; white-space: nowrap; text-overflow: ellipsis; overflow: hidden; }

.box-bottom-deco { display: flex; align-items: center; justify-content: center; gap: 3px; }
.line { height: 1px; background: #fdf2f8; flex: 1; }
.heart { font-size: 7px; color: #f472b6; }

/* ==========================================
   📄 4. 极简翻页器
   ========================================== */
.simple-pager { display: flex; justify-content: center; align-items: center; gap: 12px; margin-top: 20px; }
.simple-pager button { background: #fff; border: 1.5px solid #f1f5f9; width: 24px; height: 24px; border-radius: 50%; color: #64748b; cursor: pointer; font-size: 16px; display: flex; align-items: center; justify-content: center;}
.simple-pager span { font-size: 11px; color: #94a3b8; font-weight: bold; }
.btn-batch-del { border: none !important; width: auto !important; height: auto !important; border-radius: 6px !important; background: #f43f5e !important; color: white !important; padding: 4px 10px !important; font-size: 10px !important; font-weight: bold !important; margin-left: 10px; }
</style>