<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAudit } from '../composables/useAudit'
import UserManageBoard from '../components/UserManageBoard.vue'

const emit = defineEmits(['back-to-main'])

// 1. 本地纯 UI 状态
const activeTab = ref('audit')
const suitSearchText = ref('')
const isSuitDropdownOpen = ref(false)

// 2. 引入后台仲裁大脑
const {
  currentUserRole, currentUserId, allUsersList,
  pendingSuitsList, suitList, isSubmitting, newClothes,
  fetchAllData, fetchSuits, clusteredPendingList,
  processClusteredItem, executeSubmit, rejectPendingItem,
  approvePendingSuit, rejectPendingSuit
} = useAudit()

// 初始化加载
onMounted(() => {
  fetchAllData()
  fetchSuits()
})

// ====== 处理 UI 交互行为 ======

// 点击仲裁按钮：调用大脑处理数据，并处理界面的滚动和搜索框更新
const handleClusteredItem = (group) => {
  const matchedSuitId = processClusteredItem(group)
  const matchedSuit = suitList.value.find(s => s.id === matchedSuitId)
  suitSearchText.value = matchedSuit ? `《${matchedSuit.name}》` : ''
  window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' })
}

// 搜索下拉框相关逻辑
const selectSuit = (suit) => {
  newClothes.suit_id = suit.id
  suitSearchText.value = suit.id ? `《${suit.name}》` : ''
  isSuitDropdownOpen.value = false
}

const filteredSuits = computed(() => {
  const query = suitSearchText.value.toLowerCase().trim()
  if (!query || query.startsWith('《')) return suitList.value.slice(0, 50)
  return suitList.value.filter(s => s.name.includes(query)).slice(0, 50)
})

// 提交入库
const submitNewClothes = async () => {
  try {
    const successName = await executeSubmit()
    alert(`🎉 【${successName}】已汇聚多方数据并成功入库！`)
    suitSearchText.value = ''
  } catch (err) {
    alert('提交失败：' + err.message)
  }
}
</script>

<template>
  <div class="admin-container">
    <div class="admin-nav-tabs">
      <button class="btn-back" @click="emit('back-to-main')">⬅️ 返回玩家前台</button> 
      <button :class="{ active: activeTab === 'audit' }" @click="activeTab = 'audit'">📋 聚类审核中心</button>
      <button v-if="currentUserRole === 'super_admin'" :class="{ active: activeTab === 'users' }" @click="activeTab = 'users'">👑 全站用户与权限</button>
      <div class="role-indicator">当前登录身份：<span>{{ currentUserRole }}</span></div>
    </div>

    <div v-show="activeTab === 'audit'">
      <section class="section-card">
        <div class="section-header">
          <h3 class="purple-title">🎁 套装建档申请</h3>
          <span class="badge">{{ pendingSuitsList?.length || 0 }} 条</span>
        </div>
      
        <div class="suits-queue-container" v-if="pendingSuitsList && pendingSuitsList.length > 0">
          <div class="suit-queue-item" v-for="suit in pendingSuitsList" :key="suit.id">
            <span class="suit-queue-name">《{{ suit.name }}》</span>
            <div class="suit-queue-actions">
              <button class="btn-suit-approve" @click="approvePendingSuit(suit.id, suit.name)">✅ 批准并建档</button>
              <button class="btn-suit-reject" @click="rejectPendingSuit(suit.id)">❌</button>
            </div>
          </div>
        </div>
        <div v-else class="empty-state">
          <p>🎉 太棒了，目前没有任何套装申请待处理！</p>
        </div>
      </section>
      <section class="section-card">
        <div class="section-header">
          <h3 class="purple-title">🔔 散件众筹审核</h3>
          <span class="badge">{{ clusteredPendingList?.length || 0 }} 组待办</span>
        </div>

        <div v-if="clusteredPendingList && clusteredPendingList.length > 0" class="queue-grid">
          <div class="cluster-item" v-for="group in clusteredPendingList" :key="group.key">
            <div class="item-info-meta">
              <h4 class="item-name">{{ group.items[0].name }}</h4>
              <div class="cluster-badges">
                <span class="badge-mini cat">{{ group.items[0].category }}</span>
                <span v-if="group.items[0].game_id && group.items[0].game_id !== 'N'" class="badge-mini id">#{{ group.items[0].game_id }}</span>
                <span class="badge-mini count">🔥 {{ group.items.length }} 人提交</span>
              </div>
            </div>
            <div class="action-btns">
              <button class="btn-process" @click="handleClusteredItem(group)">✍️ 仲裁处理</button>
              <button class="btn-reject" @click="rejectPendingItem(group.items[0].id)">一键驳回</button>
            </div>
          </div>
        </div>
        <div v-else class="empty-state">
          <p>🎉 太棒了，目前没有任何散件申请待处理！</p>
        </div>
      </section>
      <section class="section-card form-section" id="entry-form">
        <div class="section-header">
          <h3 class="purple-title">👑 图鉴仲裁入库</h3>
          <span v-if="newClothes.pendingIds.length" class="edit-mode-tag">
            正在合并处理 {{ newClothes.pendingIds.length }} 份数据
          </span>
        </div>
        <div class="form-grid">
          <div class="input-group"><label>服装名称</label><input type="text" v-model="newClothes.name" /></div>
          <div class="input-group">
            <label>关联套装</label>
            <div class="searchable-select">
              <input type="text" v-model="suitSearchText" @focus="isSuitDropdownOpen = true" @blur="setTimeout(() => isSuitDropdownOpen = false, 200)" placeholder="🔍 搜索..." class="search-input" />
              <div v-if="isSuitDropdownOpen" class="select-dropdown">
                <div class="option" @click="selectSuit({id: '', name: ''})">-- 纯散件 --</div>
                <div v-for="s in filteredSuits" :key="s.id" class="option" @click="selectSuit(s)">《{{ s.name }}》</div>
              </div>
            </div>
          </div>
          <div class="input-group"><label>短编号</label><input type="text" v-model="newClothes.game_id" /></div>
          <div class="input-group">
            <label>分类部位</label>
            <select v-model="newClothes.category">
               <option v-for="cat in ['发型', '连衣裙', '外套', '上装', '下装', '袜子-袜套', '袜子-袜子', '鞋子', '妆容', '萤光之灵', '饰品-头饰-发饰', '饰品-头饰-头纱', '饰品-头饰-发卡', '饰品-头饰-耳朵', '饰品-耳饰', '饰品-颈饰-围巾', '饰品-颈饰-项链', '饰品-手饰-右', '饰品-手饰-左', '饰品-手饰-双', '饰品-手持-右', '饰品-手持-左', '饰品-手持-双', '饰品-腰饰', '饰品-特殊-面饰', '饰品-特殊-胸饰', '饰品-特殊-纹身', '饰品-特殊-翅膀', '饰品-特殊-尾巴', '饰品-特殊-前景', '饰品-特殊-后景', '饰品-特殊-顶饰', '饰品-特殊-地面', '饰品-皮肤']" :key="cat">{{cat}}</option>
            </select>
          </div>
          <div class="input-group">
            <label>星级</label>
            <select v-model="newClothes.stars">
              <option v-for="s in 6" :key="s" :value="s">{{s}} 星</option>
            </select>
          </div>
          <div class="input-group"><label>标签</label><input type="text" v-model="newClothes.tags" /></div>
        </div>

        <div class="attr-form-card">
          <p class="card-tip">🎨 智能推荐：基于 {{ newClothes.pendingIds.length || 0 }} 份数据的众数计算</p>
          <div class="attr-grid">
            <div class="attr-row" v-for="(pair, idx) in [
              {p:'pair1', g:'grade1', o:[{v:'simple',l:'简约'},{v:'gorgeous',l:'华丽'}]},
              {p:'pair2', g:'grade2', o:[{v:'cute',l:'可爱'},{v:'mature',l:'成熟'}]},
              {p:'pair3', g:'grade3', o:[{v:'active',l:'活泼'},{v:'elegant',l:'优雅'}]},
              {p:'pair4', g:'grade4', o:[{v:'pure',l:'清纯'},{v:'sexy',l:'性感'}]},
              {p:'pair5', g:'grade5', o:[{v:'cool',l:'清凉'},{v:'warm',l:'保暖'}]}
            ]" :key="idx">
              <select v-model="newClothes[pair.p]" class="attr-select">
                <option v-for="opt in pair.o" :key="opt.v" :value="opt.v">{{opt.l}}</option>
              </select>
              <select v-model="newClothes[pair.g]" class="grade-select">
                <option v-for="g in ['完美+','完美','优秀','不错','一般','失败']" :key="g">{{g}}</option>
              </select>
            </div>
          </div>
        </div>

        <button @click="submitNewClothes" class="btn-submit-all" :disabled="isSubmitting">
          {{ isSubmitting ? '⌛ 正在同步...' : (newClothes.pendingIds.length ? '✅ 仲裁完毕：一键入库并结案' : '🚀 发布新图鉴') }}
        </button>
      </section>
    </div>

  
    <div v-show="activeTab === 'users' && currentUserRole === 'super_admin'">
      <UserManageBoard 
        :allUsersList="allUsersList" 
        :currentUserId="currentUserId || ''" 
        @refresh-data="fetchAllData"
      />
    </div>
  </div>
</template>

<style scoped>
/* ==========================================
   👑 1. 顶部导航与大盘容器
   ========================================== */
.admin-container { max-width: 1200px; margin: 0 auto; padding: 20px; padding-bottom: 50px; animation: fadeIn 0.4s ease; }
.admin-nav-tabs { display: flex; gap: 15px; margin-bottom: 25px; padding: 0 5px;}
.admin-nav-tabs button { flex: 1; padding: 14px; background: white; border: 2px solid #f1f5f9; border-radius: 14px; font-size: 15px; font-weight: 900; color: #64748b; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 10px rgba(0,0,0,0.02);}
.admin-nav-tabs button.active { border-color: #f472b6; color: #db2777; background: #fdf2f8; box-shadow: 0 6px 15px rgba(244, 114, 182, 0.15);}
.btn-back { background: #f1f5f9 !important; color: #64748b !important; border-color: #e2e8f0 !important; flex: 0.5 !important; }
.btn-back:hover { background: #e2e8f0 !important; color: #334155 !important; }

.role-indicator { margin-left: auto; display: flex; align-items: center; font-size: 13px; font-weight: bold; color: #64748b; }
.role-indicator span { color: #db2777; margin-left: 5px; }

/* ==========================================
   📋 2. 聚类审核网格与卡片内部 (紧凑精致版)
   ========================================== */
.queue-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 15px; }

/* 🌟 卡片主体：增加完整边框包裹与纯白底色，彻底解决“漏风” */
.cluster-item { background: #fff; border: 1.5px solid #f3e8ff; border-radius: 16px; padding: 15px; display: flex; flex-direction: column; gap: 10px; position: relative; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.02); transition: all 0.2s; }
.cluster-item:hover { transform: translateY(-3px); border-color: #d8b4fe; box-shadow: 0 8px 20px rgba(168, 85, 247, 0.1); }
.cluster-item::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px; background: linear-gradient(90deg, #f472b6, #a855f7); }

/* 🌟 标签与文字：大幅缩小字号与内边距，改为精致小微标 */
.item-info-meta { display: flex; flex-direction: column; gap: 8px; }
.item-name { font-weight: 900; color: #1e293b; font-size: 15px; margin: 0; }
.cluster-badges { display: flex; flex-wrap: wrap; gap: 6px; }
.badge-mini { font-size: 10px; padding: 3px 6px; border-radius: 6px; font-weight: bold; display: inline-flex; align-items: center; }
.badge-mini.cat { background: #f3e8ff; color: #7e22ce; }
.badge-mini.id { background: #f1f5f9; color: #475569; }
.badge-mini.count { background: #fff1f2; color: #e11d48; border: 1px solid #fecaca; }

/* 🌟 底部按钮：整体拍扁、紧凑，更像 App 的操作区 */
.action-btns { display: flex; gap: 8px; width: 100%; margin-top: auto; padding-top: 12px; border-top: 1px dashed #f1f5f9; }
.btn-process { flex: 1; background: #faf5ff; color: #9333ea; border: 1px solid #e9d5ff; padding: 8px 0; border-radius: 8px; font-weight: 800; cursor: pointer; font-size: 12px; transition: all 0.2s; display: flex; justify-content: center; }
.btn-process:hover { background: linear-gradient(135deg, #a855f7 0%, #db2777 100%); color: white; border-color: transparent; }
.btn-reject { flex: 1; background: #f8fafc; color: #64748b; border: 1px solid #e2e8f0; padding: 8px 0; border-radius: 8px; font-weight: 800; cursor: pointer; font-size: 12px; transition: all 0.2s; display: flex; justify-content: center; }
.btn-reject:hover { background: #fff1f2; color: #e11d48; border-color: #fecaca; }
/* ==========================================
   ✍️ 3. 仲裁表单排版
   ========================================== */
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-bottom: 20px; }
.input-group label { display: block; font-size: 13px; color: #64748b; font-weight: 800; margin-bottom: 6px; }
.input-group input, .input-group select { width: 100%; padding: 10px 12px; border: 2px solid #e5e7eb; border-radius: 10px; outline: none; font-weight: bold; box-sizing: border-box;}
.input-group input:focus, .input-group select:focus { border-color: #f472b6; }

.attr-form-card { background: #fdf2f8; border-radius: 16px; padding: 20px; margin-bottom: 20px; border: 1px dashed #fbcfe8; }
.card-tip { font-size: 12px; color: #db2777; font-weight: 800; margin-bottom: 15px; }
.attr-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.attr-row { display: flex; background: white; border-radius: 10px; border: 1.5px solid #fbcfe8; overflow: hidden; }
.attr-select { flex: 1; border: none; padding: 10px; font-weight: 900; color: #7c3aed; outline: none; font-size: 14px; }
.grade-select { width: 80px; border: none; border-left: 1.5px dashed #fbcfe8; background: #fff1f2; text-align: center; font-weight: 900; color: #f472b6; cursor: pointer; outline: none; }

.btn-submit-all { width: 100%; padding: 16px; background: linear-gradient(135deg, #7c3aed 0%, #f472b6 100%); color: white; border: none; border-radius: 14px; font-size: 16px; font-weight: 900; cursor: pointer; box-shadow: 0 4px 15px rgba(124,58,237,0.3); transition: all 0.2s;}
.btn-submit-all:hover { filter: brightness(1.1); transform: translateY(-1px); }

/* ==========================================
   📱 4. 手机端专属排版适配
   ========================================== */
@media (max-width: 768px) {
  .admin-container { width: 100%; padding: 10px; }
  .admin-nav-tabs { flex-direction: column; gap: 10px; }
  .admin-nav-tabs button { padding: 12px; font-size: 14px; }
  
  .form-grid { grid-template-columns: 1fr; gap: 12px; }
  .attr-grid { grid-template-columns: 1fr; }
  
  .action-btns { flex-direction: column; width: 100%; }
  .action-btns button { width: 100%; margin-top: 5px; }
}
/* ==========================================
   🎁 5. 套装申请列表特调样式
   ========================================== */
.suits-queue-container { display: flex; flex-direction: column; gap: 10px; max-height: 280px; overflow-y: auto; padding-right: 5px; margin-bottom: 25px; }
.suits-queue-container::-webkit-scrollbar { width: 4px; }
.suits-queue-container::-webkit-scrollbar-thumb { background: #e9d5ff; border-radius: 10px; }

.suit-queue-item { display: flex; justify-content: space-between; align-items: center; background: #faf5ff; padding: 12px 16px; border-radius: 12px; border: 1px solid #f3e8ff; transition: all 0.2s; }
.suit-queue-item:hover { background: #fff; border-color: #d8b4fe; box-shadow: 0 4px 12px rgba(168, 85, 247, 0.08); transform: translateX(2px); }
.suit-queue-name { font-size: 14px; font-weight: 900; color: #7c3aed; }
.suit-queue-actions { display: flex; gap: 8px; }

.btn-suit-approve { background: #ecfdf5; color: #10b981; border: 1px solid #a7f3d0; padding: 6px 12px; border-radius: 8px; font-size: 12px; font-weight: bold; cursor: pointer; transition: all 0.2s; }
.btn-suit-approve:hover { background: #10b981; color: white; }
.btn-suit-reject { background: #fff1f2; color: #ef4444; border: 1px solid #fecaca; padding: 6px 10px; border-radius: 8px; font-size: 12px; cursor: pointer; transition: all 0.2s; }
.btn-suit-reject:hover { background: #ef4444; color: white; }
.empty-state { text-align: center; color: #94a3b8; font-size: 13px; padding: 20px 0; font-weight: bold; }
</style>