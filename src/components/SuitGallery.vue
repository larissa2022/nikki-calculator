<script setup>
import { ref, computed, watch } from 'vue'
import { contributionService } from '../api/contributionService'
import { supabase } from '../api/supabase'

const props = defineProps({
  wardrobe: { type: Array, required: true }, 
  ownedIds: { type: Array, required: true },
  isLoggedIn: { type: Boolean, default: false }
})

const emit = defineEmits(['update:ownedIds', 'save-cloud'])

const importText = ref('')
const searchQuery = ref('')
const isRecognizing = ref(false)

const filterStatus = ref('all') 
const currentPage = ref(1)
const pageSize = 24 

// 🌟 弹窗与临时状态管理
const selectedSuit = ref(null)
const localOwnedIds = ref([]) // 用于在弹窗中暂存勾选状态

watch([searchQuery, filterStatus], () => {
  currentPage.value = 1
})

// 🌟 监听弹窗打开，克隆一份当前的拥有状态
watch(selectedSuit, (newSuit) => {
  if (newSuit) {
    localOwnedIds.value = [...props.ownedIds]
  }
})

// ====== 🌟 新增：单件点击切换逻辑 ======
const togglePart = (partId) => {
  const index = localOwnedIds.value.indexOf(partId)
  if (index > -1) {
    localOwnedIds.value.splice(index, 1) // 已有则移除
  } else {
    localOwnedIds.value.push(partId) // 未有则添加
  }
}

// ====== 🌟 新增：确认并保存修改 ======
const confirmSuitChanges = () => {
  emit('update:ownedIds', localOwnedIds.value)
  if (props.isLoggedIn) emit('save-cloud')
  selectedSuit.value = null // 关闭弹窗
  // 这里可以加一个轻提示
}

// ====== 引擎 1：动态聚合出所有套装 ======
const allSuits = computed(() => {
  const suitMap = {}
  
  props.wardrobe.forEach(item => {
    const sName = item.suit_name?.trim()
    if (sName) {
      if (!suitMap[sName]) suitMap[sName] = []
      suitMap[sName].push(item)
    }
  })

  return Object.keys(suitMap).map(name => {
    const parts = suitMap[name]
    const partIds = parts.map(p => p.id)
    const ownedCount = partIds.filter(id => props.ownedIds.includes(id)).length
    return {
      name,
      parts,
      partIds,
      total: parts.length,
      owned: ownedCount,
      isComplete: ownedCount === parts.length,
      percent: Math.floor((ownedCount / parts.length) * 100)
    }
  }).sort((a, b) => {
    if (a.isComplete === b.isComplete) return b.percent - a.percent
    return a.isComplete ? 1 : -1
  })
})

const filteredSuits = computed(() => {
  let result = allSuits.value
  const query = searchQuery.value.trim()
  if (query) result = result.filter(s => s.name.includes(query))
  if (filterStatus.value === 'completed') result = result.filter(s => s.isComplete)
  else if (filterStatus.value === 'incomplete') result = result.filter(s => !s.isComplete)
  return result
})

const totalPages = computed(() => Math.ceil(filteredSuits.value.length / pageSize))
const paginatedSuits = computed(() => {
  const start = (currentPage.value - 1) * pageSize
  return filteredSuits.value.slice(start, start + pageSize)
})

// ====== AI 扫描与批量导入 ======
const compressImage = (file) => {
  return new Promise((resolve) => {
    const reader = new FileReader()
    reader.readAsDataURL(file)
    reader.onload = (e) => {
      const img = new Image()
      img.src = e.target.result
      img.onload = () => {
        const canvas = document.createElement('canvas')
        const MAX_WIDTH = 800
        let width = img.width
        let height = img.height
        if (width > MAX_WIDTH) {
          height = Math.round((height * MAX_WIDTH) / width)
          width = MAX_WIDTH
        }
        canvas.width = width
        canvas.height = height
        const ctx = canvas.getContext('2d')
        ctx.drawImage(img, 0, 0, width, height)
        resolve(canvas.toDataURL('image/jpeg', 0.7))
      }
    }
  })
}

const onFileChange = async (event) => {
  const file = event.target.files[0]
  if (!file) return
  isRecognizing.value = true 
  try {
    const compressedBase64 = await compressImage(file)
    const data = await contributionService.recognizeImage(compressedBase64, 'suit')
    importText.value = data.names
    if (error) throw error
    importText.value = data.names
    handleSuitImport()
  } catch (err) {
    alert(`识别失败: ${err.message}`)
  } finally {
    isRecognizing.value = false
    event.target.value = '' 
  }
}

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
    } else { notFound.push(name) }
  })

  if (addedCount > 0) {
    emit('update:ownedIds', updatedOwnedIds)
    if (props.isLoggedIn) emit('save-cloud')
    alert(`✨ 琉璃共鸣！成功录入了 ${addedCount} 个套装部件！`)
  } else if (notFound.length === 0) {
    alert('没有录入新部件，可能是已经集齐啦。')
  }

  if (notFound.length > 0) {
    const missingStr = notFound.join('、')
    const wantToSubmit = confirm(`⚠️ 以下套装数据库里还没有：\n${missingStr}\n\n是否要向管理员提报收录这些新套装？`)
    if (wantToSubmit) submitMissingSuits(notFound)
  }
  importText.value = ''
}

const unlockSingleSuit = (suit) => {
  const updatedOwnedIds = [...props.ownedIds]
  suit.partIds.forEach(id => {
    if (!updatedOwnedIds.includes(id)) updatedOwnedIds.push(id)
  })
  emit('update:ownedIds', updatedOwnedIds)
  if (props.isLoggedIn) emit('save-cloud')
}

const submitMissingSuits = async (namesArray) => {
  if (!props.isLoggedIn) return alert('请先登录后再提报新套装哦~')
  try {
    const { data: { user } } = await supabase.auth.getUser()
    // 🌟 核心替换：呼叫服务专员
    await contributionService.submitMissingSuits(namesArray, user.id)
    alert('✅ 提报成功！已发送给管理员审核，感谢你的贡献！')
  } catch (err) {
    alert(err.message) // 这样就能精准弹出 API 里的报错信息了
  }
}
</script>

<template>
  <div class="suit-gallery">
    
    <div class="batch-import-zone">
      <div class="zone-header">
        <h2>🎁 唤醒套装特区</h2>
        <span class="sub-title">光速点亮全图鉴的终极捷径</span>
      </div>

      <div class="ai-scan-zone">
        <label class="btn-scan" :class="{ 'scanning': isRecognizing }">
          <span v-if="!isRecognizing">📸 上传【套装图鉴】截图识别</span>
          <span v-else>🔍 AI 正在提取套装基因...</span>
          <input type="file" accept="image/*" @change="onFileChange" :disabled="isRecognizing" hidden />
        </label>
      </div>

      <div class="import-controls">
        <textarea v-model="importText" rows="2" placeholder="或者在这里直接输入套装名字（如：星之海, 韶颜倾城），用逗号或空格隔开..."></textarea>
        <button class="btn-primary" @click="handleSuitImport">一键全部集齐</button>
      </div>
    </div>

    <div class="divider"><span class="heart-deco">♥</span></div>

    <div class="visual-gallery-zone">
      <div class="gallery-header-row">
        <h3>✨ 套装典藏馆</h3>
        <div class="header-controls">
          <div class="filter-tabs">
            <button :class="{ active: filterStatus === 'all' }" @click="filterStatus = 'all'">全部</button>
            <button :class="{ active: filterStatus === 'completed' }" @click="filterStatus = 'completed'">已集齐</button>
            <button :class="{ active: filterStatus === 'incomplete' }" @click="filterStatus = 'incomplete'">未集齐</button>
          </div>
          <input type="text" v-model="searchQuery" class="search-box" placeholder="搜索套装..." />
        </div>
      </div>

      <div class="suit-grid" v-if="paginatedSuits.length > 0">
        <div 
          v-for="suit in paginatedSuits" 
          :key="suit.name" 
          class="suit-card" 
          :class="{ 'is-complete': suit.isComplete }"
          @click="selectedSuit = suit"
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

          <button class="btn-unlock" v-if="!suit.isComplete" @click.stop="unlockSingleSuit(suit)">一键补齐部件</button>
        </div>
      </div>
      
      <div v-else class="empty-state"><p>没有找到符合条件的套装哦~</p></div>

      <div class="pagination" v-if="totalPages > 1">
        <button class="page-btn" :disabled="currentPage === 1" @click="currentPage--">◀ 上一页</button>
        <div class="page-info"><span class="current">{{ currentPage }}</span> / <span class="total">{{ totalPages }}</span></div>
        <button class="page-btn" :disabled="currentPage === totalPages" @click="currentPage++">下一页 ▶</button>
      </div>
    </div>


    <Teleport to="body">
      <Transition name="fade">
        <div v-if="selectedSuit" class="modal-overlay" @click.self="selectedSuit = null">
          <div class="modal-content detail-modal">
            <div class="modal-header">
              <h3>《{{ selectedSuit.name }}》部件清单</h3>
              <button class="btn-close" @click="selectedSuit = null">×</button>
            </div>
            
            <div class="modal-subtitle">点击部件可快速切换拥有状态</div>

            <div class="parts-list">
              <div 
                v-for="part in selectedSuit.parts" 
                :key="part.id" 
                class="part-item clickable-part"
                :class="{ 'owned': localOwnedIds.includes(part.id) }"
                @click="togglePart(part.id)"
              >
                <div class="part-status-dot"></div>
                <span class="part-cat">[{{ part.category }}]</span>
                <span class="part-name">{{ part.name }}</span>
                <span class="owned-tag" v-if="localOwnedIds.includes(part.id)">已拥有</span>
                <span class="unowned-tag" v-else>未拥有</span>
              </div>
            </div>

            <div class="modal-actions">
              <button class="btn-primary" @click="confirmSuitChanges">
                ✅ 确认并保存修改
              </button>
              <button 
                class="btn-outline" 
                v-if="localOwnedIds.filter(id => selectedSuit.partIds.includes(id)).length < selectedSuit.total"
                @click="localOwnedIds.push(...selectedSuit.partIds.filter(id => !localOwnedIds.includes(id)))"
              >
                ✨ 一键补齐当前套装
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

  </div>
</template>

<style scoped>
/* 🌟 全局盒子模型修正，防止撑破边缘 */
* { box-sizing: border-box; }

/* ========================================== */
/* 🌟 1. 核心容器排版（解决占满全屏问题） */
/* ========================================== */
.suit-gallery {
  /* 🌟 不要用 1200px 了，改成 100%，让它乖乖填满 App.vue 里的 680px 容器即可 */
  width: 100%; 
  /* 🌟 移除多余的内外边距，因为它已经在那个玻璃面板里了 */
  padding: 0; 
  margin: 0;
  animation: fadeIn 0.4s ease;
}

.glass-panel { 
  background: transparent; 
  border: none; 
  padding: 0; 
  box-shadow: none; 
}

/* ========================================== */
/* 🌟 2. 唤醒套装特区 & 顶部工具栏 */
/* ========================================== */
.zone-header { margin-bottom: 12px; }
.zone-header h2 { margin: 0; color: #db2777; font-size: 18px; font-weight: 900; }
.sub-title { font-size: 11px; color: #94a3b8; font-weight: bold; }

.btn-scan { display: block; width: 100%; text-align: center; background: linear-gradient(135deg, #7c3aed 0%, #f472b6 100%); color: white; padding: 12px; border-radius: 14px; font-size: 13px; font-weight: 800; cursor: pointer; transition: all 0.3s; box-shadow: 0 4px 15px rgba(124, 58, 237, 0.2); margin-bottom: 15px; }
.btn-scan:hover { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(124, 58, 237, 0.3); }
.btn-scan.scanning { filter: grayscale(1); cursor: wait; }

.import-controls { display: flex; flex-direction: column; gap: 10px; }
textarea { width: 100%; padding: 12px; border: 1.5px solid #f1f5f9; border-radius: 14px; background: rgba(255,255,255,0.6); outline: none; resize: vertical; font-size: 13px; transition: all 0.3s; }
textarea:focus { border-color: #f472b6; background: #fff; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }

.btn-primary { background: linear-gradient(135deg, #a855f7 0%, #d946ef 100%); color: white; border: none; padding: 12px; border-radius: 14px; font-weight: bold; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 15px rgba(217, 70, 239, 0.2); }
.btn-primary:hover { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(217, 70, 239, 0.3); }

.divider { display: flex; align-items: center; justify-content: center; margin: 25px 0; position: relative; }
.divider::before, .divider::after { content: ''; flex: 1; height: 1.5px; background: #fbcfe8; }
.heart-deco { margin: 0 15px; color: #f472b6; font-size: 14px; }

/* ========================================== */
/* 🌟 3. 套装列表网格（精致 4 列版） */
/* ========================================== */
.gallery-header-row { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; flex-wrap: wrap; gap: 15px; }
.gallery-header-row h3 { margin: 0; color: #9333ea; font-size: 16px; font-weight: 900; }
.header-controls { display: flex; gap: 15px; align-items: center; flex-wrap: wrap; }

.filter-tabs { display: flex; background: #f8fafc; padding: 4px; border-radius: 12px; border: 1px solid #e2e8f0; }
.filter-tabs button { background: transparent; border: none; padding: 6px 12px; font-size: 12px; font-weight: bold; color: #64748b; border-radius: 8px; cursor: pointer; transition: all 0.2s; }
.filter-tabs button.active { background: white; color: #9333ea; box-shadow: 0 2px 6px rgba(0,0,0,0.05); }

.search-box { padding: 8px 15px; border: 1.5px solid #e9d5ff; border-radius: 20px; font-size: 12px; outline: none; width: 140px; background: #faf5ff; transition: all 0.3s; }
.search-box:focus { border-color: #c084fc; width: 180px; background: #fff; }

.suit-grid { 
  display: grid; 
  /* 🌟 核心修改：强制一行 4 个，平分剩余空间 */
  grid-template-columns: repeat(4, 1fr); 
  gap: 12px; /* 🌟 缩小卡片间距，腾出更多空间 */
}

/* 👇 卡片整体精简化，适应窄横幅 */
.suit-card { 
  background: white; 
  border: 1.5px solid #f3e8ff; 
  border-radius: 12px; /* 缩小圆角 */
  padding: 12px;       /* 缩小内边距 */
  display: flex; 
  flex-direction: column; 
  gap: 8px;            /* 内部元素挨得更紧密 */
  cursor: pointer; 
  transition: all 0.2s; 
  box-shadow: 0 4px 12px rgba(0,0,0,0.02); 
}
.suit-card:hover { transform: translateY(-3px); border-color: #d8b4fe; box-shadow: 0 8px 20px rgba(168, 85, 247, 0.1); }
.suit-card.is-complete { background: #fdf2f8; border-color: #fbcfe8; }

.card-top { display: flex; justify-content: space-between; align-items: flex-start; gap: 4px; }
/* 🌟 防止套装名字太长撑破卡片，加入单行省略号 */
.suit-name { font-size: 13px; font-weight: 900; color: #475569; flex-grow: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.suit-badge { background: #f472b6; color: white; font-size: 9px; font-weight: bold; padding: 2px 4px; border-radius: 6px; flex-shrink: 0;}

.progress-section { display: flex; flex-direction: column; gap: 5px; }
.progress-info { display: flex; justify-content: space-between; align-items: center; }
.percent-num { font-size: 13px; font-weight: 900; color: #a855f7; }
.count-num { font-size: 10px; color: #94a3b8; font-family: monospace; font-weight: bold; }
.progress-track { height: 6px; background: #f1f5f9; border-radius: 10px; overflow: hidden; }
.progress-fill { height: 100%; background: linear-gradient(90deg, #c084fc 0%, #d946ef 100%); border-radius: 10px; transition: width 0.5s ease; }
.is-complete .progress-fill { background: linear-gradient(90deg, #fbcfe8 0%, #f472b6 100%); }

/* 🌟 按钮缩小排版 */
.btn-unlock { background: #fff; border: 1.5px solid #d8b4fe; color: #9333ea; font-size: 11px; font-weight: bold; padding: 6px; border-radius: 8px; cursor: pointer; transition: all 0.2s; margin-top: auto; }
.btn-unlock:hover { background: #9333ea; color: white; }
.empty-state { text-align: center; color: #94a3b8; font-size: 13px; padding: 30px 0; grid-column: span 4; }
.pagination { display: flex; justify-content: center; align-items: center; gap: 20px; margin-top: 30px; }
.page-btn { background: #fff; border: 1.5px solid #e2e8f0; color: #475569; padding: 8px 16px; border-radius: 10px; font-size: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s; }
.page-btn:not(:disabled):hover { border-color: #a855f7; color: #9333ea; box-shadow: 0 4px 10px rgba(168, 85, 247, 0.1); }
.page-btn:disabled { opacity: 0.5; cursor: not-allowed; background: #f8fafc; }
.page-info { font-size: 13px; color: #64748b; font-weight: bold; }
.page-info .current { color: #9333ea; font-size: 15px; }

/* ========================================== */
/* 🌟 4. 弹窗与部件列表双列美化 */
/* ========================================== */
.modal-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 2000; backdrop-filter: blur(4px); }
.detail-modal { 
  width: 90%; 
  max-width: 650px; /* 🌟 放大 PC 端弹窗宽度以适应双列 */
  background: white; 
  border-radius: 24px; 
  padding: 25px; 
  box-shadow: 0 20px 50px rgba(0,0,0,0.2); 
  display: flex; 
  flex-direction: column; 
  max-height: 85vh; 
}
.modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px; border-bottom: 2px dashed #fdf2f8; padding-bottom: 12px; }
.modal-header h3 { margin: 0; color: #db2777; font-size: 18px; }
.modal-subtitle { font-size: 11px; color: #a855f7; margin-bottom: 15px; font-weight: bold; text-align: center; }
.btn-close { background: #f1f5f9; border: none; font-size: 24px; color: #94a3b8; cursor: pointer; border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; }

/* 🌟 PC 端部件列表：双列网格布局 */
.parts-list { 
  display: grid;
  grid-template-columns: 1fr 1fr; /* 双列展示，告别一条长到底 */
  gap: 12px;
  overflow-y: auto; 
  padding-right: 5px; 
  margin-bottom: 20px;
}
.parts-list::-webkit-scrollbar { width: 4px; }
.parts-list::-webkit-scrollbar-thumb { background: #fbcfe8; border-radius: 10px; }

.part-item { display: flex; align-items: center; gap: 8px; padding: 10px 12px; background: #f8fafc; border-radius: 12px; border: 1.5px solid #e2e8f0; transition: all 0.2s; }
.part-item.owned { background: #fdf2f8; border-color: #fbcfe8; }
.part-status-dot { width: 8px; height: 8px; background: #cbd5e1; border-radius: 50%; transition: all 0.2s; flex-shrink: 0;}
.owned .part-status-dot { background: #f472b6; box-shadow: 0 0 8px rgba(244, 114, 182, 0.5); }
.part-cat { font-size: 12px; color: #94a3b8; font-weight: bold; flex-shrink: 0;}
.part-name { font-size: 14px; font-weight: 800; color: #475569; flex-grow: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;}
.owned-tag { font-size: 10px; background: #f472b6; color: white; padding: 3px 6px; border-radius: 8px; font-weight: bold; flex-shrink: 0;}
.unowned-tag { font-size: 10px; background: #f1f5f9; color: #94a3b8; padding: 3px 6px; border-radius: 8px; font-weight: bold; flex-shrink: 0;}

.clickable-part { cursor: pointer; user-select: none; }
.clickable-part:hover { transform: scale(1.02); box-shadow: 0 4px 12px rgba(219, 39, 119, 0.08); border-color: #f472b6; }

.modal-actions { display: flex; flex-direction: column; gap: 10px; }
.btn-outline { background: white; color: #a855f7; border: 1.5px solid #d8b4fe; padding: 12px; border-radius: 14px; font-weight: bold; cursor: pointer; transition: all 0.2s; font-size: 14px;}
.btn-outline:hover { background: #faf5ff; border-color: #a855f7; }

/* ========================================== */
/* 📱 5. 手机端专属适配策略 */
/* ========================================== */
@media (max-width: 768px) {
  .suit-gallery { padding: 10px; }
  
  /* 手机端每行显示 2 个套装 */
  .suit-grid { grid-template-columns: 1fr 1fr; gap: 12px; }
  .suit-card { padding: 12px; }
  .suit-name { font-size: 13px; }
  
  /* 弹窗占满手机屏幕宽度（留一点边），高度缩小 */
  .detail-modal { width: 92% !important; max-width: none; padding: 18px !important; }
  
  /* 手机端太窄了，改回单列展示部件，防止文字挤重叠 */
  .parts-list { grid-template-columns: 1fr; gap: 8px; }
}

.fade-enter-active, .fade-leave-active { transition: opacity 0.3s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
</style>