<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAudit } from '../composables/useAudit'
import UserManageBoard from '../components/UserManageBoard.vue'
import { GRADE_OPTIONS } from '../composables/useScoreEngine'
import ScoreAttributePanel from '../components/ScoreAttributePanel.vue'

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
// 🌟 1. 新增：消消乐模式的排队与热度排序逻辑
// 🌟 1. 新增：消消乐模式的排队与热度排序逻辑
const sortedPendingList = computed(() => {
  if (!clusteredPendingList.value) return []
  // 按照玩家提交人数（items.length）降序排列，越热门的越靠前
  return [...clusteredPendingList.value].sort((a, b) => b.items.length - a.items.length)
})
// 永远只显示前 6 个，审核掉一个，下一个自动补位
const displayPendingList = computed(() => sortedPendingList.value.slice(0, 6))

// 🌟 2. 新增：套装申请列表的去重与热度统计
const uniquePendingSuits = computed(() => {
  if (!pendingSuitsList.value) return []
  const map = new Map()
  pendingSuitsList.value.forEach(suit => {
    // 利用套装名称作为唯一标识进行去重归类
    if (!map.has(suit.name)) {
      map.set(suit.name, { ...suit, count: 1 })
    } else {
      map.get(suit.name).count++
    }
  })
  // 按提交申请的人数降序排列，越多人申请的套装越靠前
  return Array.from(map.values()).sort((a, b) => b.count - a.count)
})
// 🌟 补回刚才不小心删掉的初始化加载钩子！
onMounted(() => {
  fetchAllData()
  fetchSuits()
})
// 初始化加载

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
  <div class="max-w-5xl mx-auto p-4 md:p-6 min-h-screen pb-20 animate-[fadeIn_0.4s_ease]">
    
    <div class="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 bg-white/80 backdrop-blur-md p-4 rounded-2xl shadow-sm mb-6 border border-slate-100">
      <button class="btn btn-sm btn-ghost bg-slate-100 text-slate-600 font-bold hover:bg-slate-200" @click="emit('back-to-main')">
        ⬅️ 返回玩家前台
      </button>
      <div class="flex items-center gap-2 text-sm font-bold text-slate-500">
        当前登录身份：<span class="badge badge-primary badge-outline font-black">{{ currentUserRole }}</span>
      </div>
    </div>

    <div class="tabs tabs-boxed bg-white/60 p-1 mb-6 shadow-sm border border-slate-100 rounded-xl">
      <a class="tab font-bold text-sm h-10 flex-1 transition-all" 
         :class="{'tab-active !bg-primary !text-white shadow-md': activeTab === 'audit'}" 
         @click="activeTab = 'audit'">📋 聚类审核中心</a>
      <a v-if="currentUserRole === 'super_admin'" 
         class="tab font-bold text-sm h-10 flex-1 transition-all" 
         :class="{'tab-active !bg-primary !text-white shadow-md': activeTab === 'users'}" 
         @click="activeTab = 'users'">👑 全站用户与权限</a>
    </div>

    <div v-show="activeTab === 'audit'" class="space-y-6">
      
      <section class="bg-white p-5 md:p-6 rounded-2xl shadow-sm border border-slate-100">
        <div class="flex justify-between items-center mb-4 pb-3 border-b border-slate-50">
          <h3 class="text-lg md:text-xl font-black text-purple-600 m-0">🎁 套装建档申请</h3>
          <span class="badge badge-sm badge-ghost font-bold">{{ uniquePendingSuits.length }} 组待办</span>
        </div>
        
        <div v-if="uniquePendingSuits.length > 0" class="flex flex-col gap-2 max-h-[280px] overflow-y-auto pr-2 custom-scroll">
          <div v-for="suit in uniquePendingSuits" :key="suit.name" class="flex justify-between items-center bg-slate-50 hover:bg-white p-3 md:p-4 rounded-xl border border-slate-100 hover:border-purple-200 transition-all shadow-sm">
            
            <div class="flex items-center gap-2">
              <span class="font-black text-purple-600 text-sm">《{{ suit.name }}》</span>
              <span v-if="suit.count > 1" class="text-[10px] font-bold bg-rose-50 text-rose-600 border border-rose-100 px-2 py-0.5 rounded-md">
                🔥 {{ suit.count }} 人提交
              </span>
            </div>
            
            <div class="flex gap-2">
              <button class="btn btn-xs md:btn-sm btn-success text-white font-bold" @click="approvePendingSuit(suit.id, suit.name)">✅ 批准建档</button>
              <button class="btn btn-xs md:btn-sm btn-error btn-outline font-bold" @click="rejectPendingSuit(suit.id)">❌</button>
            </div>
          </div>
        </div>
        <div v-else class="py-8 text-center text-slate-400 font-bold text-sm bg-slate-50/50 rounded-xl border border-dashed border-slate-200">
          🎉 太棒了，目前没有任何套装申请待处理！
        </div>
      </section>

      <section class="bg-white p-5 md:p-6 rounded-2xl shadow-sm border border-slate-100">
        <div class="flex justify-between items-center mb-4 pb-3 border-b border-slate-50">
          <h3 class="text-lg md:text-xl font-black text-pink-500 m-0">🔔 散件众筹审核</h3>
          <span class="badge badge-sm badge-ghost font-bold">{{ clusteredPendingList?.length || 0 }} 组待办</span>
        </div>

        <div v-if="sortedPendingList && sortedPendingList.length > 0" class="flex flex-col gap-4">
          <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            <div v-for="group in displayPendingList" :key="group.key" class="bg-white border-2 border-slate-100 hover:border-purple-200 rounded-2xl p-4 flex flex-col gap-3 relative overflow-hidden shadow-sm transition-all hover:shadow-md hover:-translate-y-1">
              <div class="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-pink-400 to-purple-500"></div>
              
              <div class="flex flex-col gap-2">
                <h4 class="font-black text-slate-800 text-base m-0">{{ group.items[0].name }}</h4>
                <div class="flex flex-wrap gap-1.5">
                  <span class="text-[10px] font-bold bg-purple-50 text-purple-600 px-2 py-0.5 rounded-md">{{ group.items[0].category }}</span>
                  <span v-if="group.items[0].game_id && group.items[0].game_id !== 'N'" class="text-[10px] font-bold bg-slate-100 text-slate-600 px-2 py-0.5 rounded-md">#{{ group.items[0].game_id }}</span>
                  <span class="text-[10px] font-bold bg-rose-50 text-rose-600 border border-rose-100 px-2 py-0.5 rounded-md">🔥 {{ group.items.length }} 人提交</span>
                </div>
              </div>
              
              <div class="grid grid-cols-2 gap-2 mt-auto pt-3 border-t border-dashed border-slate-100">
                <button class="btn btn-sm px-0 text-xs whitespace-nowrap bg-purple-50 text-purple-600 border-purple-100 hover:bg-purple-500 hover:text-white transition-all" @click="handleClusteredItem(group)">✍️ 仲裁</button>
                <button class="btn btn-sm px-0 text-xs whitespace-nowrap bg-slate-50 text-slate-500 border-slate-200 hover:bg-rose-500 hover:text-white transition-colors" @click="rejectPendingItem(group.items[0].id)">🗑️ 驳回</button>
              </div>
            </div>
          </div>
          
          <div v-if="sortedPendingList.length > 6" class="text-center py-2 text-xs font-bold text-slate-400 bg-slate-50 rounded-xl border border-dashed border-slate-200">
            👇 还有 {{ sortedPendingList.length - 6 }} 组申请正在排队...
          </div>
        </div>
        <div v-else class="py-8 text-center text-slate-400 font-bold text-sm bg-slate-50/50 rounded-xl border border-dashed border-slate-200">
          🎉 太棒了，目前没有任何散件申请待处理！
        </div>
      </section>

      <section id="entry-form" class="bg-white p-5 md:p-6 rounded-2xl shadow-sm border border-slate-100 border-t-4 border-t-primary mt-6">
        <div class="flex flex-col md:flex-row justify-between items-start md:items-center gap-2 mb-5 pb-4 border-b border-slate-50">
          <h3 class="text-lg md:text-xl font-black text-slate-800 m-0">👑 图鉴仲裁入库</h3>
          <span v-if="newClothes.pendingIds.length" class="text-xs font-bold bg-emerald-50 text-emerald-600 px-3 py-1 rounded-full border border-emerald-100">
            正在合并处理 {{ newClothes.pendingIds.length }} 份玩家数据
          </span>
        </div>
        
        <div class="mini-form-body">
          
          <div class="form-row" style="grid-template-columns: 1fr;">
            <div class="form-group">
              <label>服装名称</label>
              <input type="text" v-model="newClothes.name" class="custom-input" placeholder="确认官方精准名称" />
            </div>
          </div>
          
          <div class="form-row" style="grid-template-columns: 1fr;">
            <div class="form-group">
              <label>归属套装</label>
              <div style="display: flex; gap: 8px;">
                <div class="searchable-select" style="flex: 1;">
                  <input 
                    type="text" 
                    v-model="suitSearchText" 
                    @focus="isSuitDropdownOpen = true"
                    @blur="setTimeout(() => isSuitDropdownOpen = false, 200)"
                    placeholder="🔍 搜索并选择套装..."
                    class="search-input"
                  />
                  <Transition name="slide">
                    <div v-if="isSuitDropdownOpen" class="select-dropdown">
                      <div class="option" @click="selectSuit({id: '', name: ''})">-- 纯散件 (无关联套装) --</div>
                      <div v-for="s in filteredSuits" :key="s.id" class="option" @click="selectSuit(s)">
                        《{{ s.name }}》
                      </div>
                    </div>
                  </Transition>
                </div>
              </div>
            </div>
          </div>
          
          <div class="form-row three-cols">
            <div class="form-group">
              <label>短编号(如001)</label>
              <input type="text" v-model="newClothes.game_id" class="custom-input" placeholder="选填" />
            </div>
            <div class="form-group">
              <label>分类部位</label>
              <select v-model="newClothes.category" class="custom-input">
                <option v-for="cat in ['发型', '连衣裙', '外套', '上装', '下装', '袜子-袜套', '袜子-袜子', '鞋子', '妆容', '萤光之灵', '饰品-头饰-发饰', '饰品-头饰-头纱', '饰品-头饰-发卡', '饰品-头饰-耳朵', '饰品-耳饰', '饰品-颈饰-围巾', '饰品-颈饰-项链', '饰品-手饰-右', '饰品-手饰-左', '饰品-手饰-双', '饰品-手持-右', '饰品-手持-左', '饰品-手持-双', '饰品-腰饰', '饰品-特殊-面饰', '饰品-特殊-胸饰', '饰品-特殊-纹身', '饰品-特殊-翅膀', '饰品-特殊-尾巴', '饰品-特殊-前景', '饰品-特殊-后景', '饰品-特殊-顶饰', '饰品-特殊-地面', '饰品-皮肤']" :key="cat">{{cat}}</option>
              </select>
            </div>
            <div class="form-group">
              <label>星级</label>
              <select v-model="newClothes.stars" class="custom-input">
                <option v-for="s in 6" :key="s" :value="s">{{s}} 星</option>
              </select>
            </div>
          </div>
          
          <div class="form-row">
            <div class="form-group">
              <label>特殊标签</label>
              <input type="text" v-model="newClothes.tags" class="custom-input" placeholder="如: 洛丽塔, 中式古典..." />
            </div>
          </div>

          <div class="bg-pink-50/40 border border-pink-100 border-dashed rounded-2xl p-4 md:p-5 mb-5 mt-3">
            <p class="text-xs text-pink-600 font-bold mb-4">🎨 智能推荐：基于 {{ newClothes.pendingIds.length || 0 }} 份数据的众数计算</p>
            <ScoreAttributePanel :form="newClothes" />
          </div>

          <button class="btn-submit-contrib w-full" @click="submitNewClothes" :disabled="isSubmitting">
            <span v-if="isSubmitting" class="loading loading-spinner loading-sm mr-2 inline-block"></span>
            {{ isSubmitting ? '正在合并入库...' : (newClothes.pendingIds.length ? '✅ 仲裁完毕：一键入库并结案' : '🚀 发布全新图鉴') }}
          </button>

        </div>
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
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

.custom-scroll::-webkit-scrollbar { width: 5px; }
.custom-scroll::-webkit-scrollbar-thumb { background: #e2e8f0; border-radius: 10px; }
.custom-scroll::-webkit-scrollbar-track { background: transparent; }
</style> 