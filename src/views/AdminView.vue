<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAudit } from '../composables/useAudit'
import UserManageBoard from '../components/UserManageBoard.vue'
import { supabase } from '../api/supabase' // 🌟 新增这一行：引入数据库实例
import ClothesEntryForm from '../components/ClothesEntryForm.vue'
import { isSuperAdminRole } from '../utils/roles'
const emit = defineEmits(['back-to-main'])

// 1. 本地纯 UI 状态
const activeTab = ref('audit')
const suitSearchText = ref('')
const activeAuditFilter = ref('all')
const isRejecting = ref(false)

// 2. 引入后台仲裁大脑
const {
  currentUserRole, currentUserId, allUsersList,
  pendingSuitsList, suitList, isSubmitting, newClothes, auditSelectionInfo,
  fetchAllData, fetchSuits, clusteredPendingList,
  processClusteredItem, executeSubmit, rejectPendingItem,
  approvePendingSuit, rejectPendingSuit
} = useAudit()
// 🌟 1. 新增：消消乐模式的排队与热度排序逻辑
// 🌟 1. 新增：消消乐模式的排队与热度排序逻辑
const sortedPendingList = computed(() => {
  if (!clusteredPendingList.value) return []
  return [...clusteredPendingList.value].sort((a, b) => (
    a.riskRank - b.riskRank
    || b.topSubmitterCount - a.topSubmitterCount
    || b.distinctSubmitterCount - a.distinctSubmitterCount
    || b.items.length - a.items.length
  ))
})
const auditFilterOptions = computed(() => {
  const list = sortedPendingList.value
  const countBy = (predicate) => list.filter(predicate).length
  return [
    { key: 'all', label: '全部', count: list.length },
    { key: 'ready', label: '可入库', count: countBy(group => group.candidateStatus === 'ready') },
    { key: 'conflict', label: '有不同意见', count: countBy(group => group.candidateStatus === 'conflict' || group.candidateStatus === 'weak_conflict' || group.candidateStatus === 'known_mismatch') },
    { key: 'known', label: '正式库已有', count: countBy(group => group.candidateStatus === 'known') },
    { key: 'insufficient', label: '人数不足', count: countBy(group => group.candidateStatus === 'insufficient') },
    { key: 'legacy', label: '匿名历史数据', count: countBy(group => group.candidateStatus === 'legacy') }
  ]
})
const filteredPendingList = computed(() => {
  if (activeAuditFilter.value === 'all') return sortedPendingList.value
  if (activeAuditFilter.value === 'conflict') {
    return sortedPendingList.value.filter(group => group.candidateStatus === 'conflict' || group.candidateStatus === 'weak_conflict' || group.candidateStatus === 'known_mismatch')
  }
  return sortedPendingList.value.filter(group => group.candidateStatus === activeAuditFilter.value)
})
// 每次只展示一屏申请，审核掉一个，下一个自动补位
const displayPendingList = computed(() => filteredPendingList.value.slice(0, 9))
const auditSubmitText = computed(() => {
  if (auditSelectionInfo.value?.requiresManualReview) return '需重审 / 人工处理'
  if (auditSelectionInfo.value?.canCompleteExisting) return '补全正式库已有记录'
  return newClothes.pendingIds.length ? '✅ 仲裁完毕：一键入库并结案' : '🚀 发布全新图鉴'
})
const auditSubmitLoadingText = computed(() => (
  auditSelectionInfo.value?.canCompleteExisting ? '正在补全正式库...' : '正在合并入库...'
))

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
// 🌟 新增：极速顺手创建套装逻辑
const quickCreateSuit = async (newSuitName) => {
  // 帮你把玩家可能乱输入的书名号和空格洗掉
  const cleanName = newSuitName.replace(/[《》]/g, '').trim()
  if (!cleanName) return

  try {
    // 1. 直接往数据库正规军库里插入新套装
    const { data, error } = await supabase
      .from('suits')
      .insert([{ name: cleanName }])
      .select()
      .single()
      
    if (error && error.code !== '23505') throw error // 忽略可能存在的同名并发错误
    
    alert(`✅ 套装《${cleanName}》已秒建成功！`)
    
    // 2. 重新拉取全局套装列表，让刚才建的套装生效
    await fetchSuits() 
    
    // 3. 自动帮你把新建的套装填入当前的审核表单中！
    const newlyCreated = suitList.value.find(s => s.name === cleanName)
    if (newlyCreated) {
      selectSuit(newlyCreated)
    } else if (data) {
      // 兜底：如果刚插入还没来得及同步，直接用插入返回的数据
      selectSuit(data)
    }
    
  } catch (err) {
    alert('极速创建套装失败: ' + err.message)
  }
}
// 🌟 补回刚才不小心删掉的初始化加载钩子！
onMounted(() => {
  fetchAllData()
  fetchSuits()
})
// 初始化加载

// ====== 处理 UI 交互行为 ======

// 点击仲裁按钮：调用大脑处理数据，并处理界面的滚动和搜索框更新
const handleClusteredItem = (group) => {
  const pendingSuitState = processClusteredItem(group)
  const matchedSuit = suitList.value.find(s => s.id === pendingSuitState.suitId)
  suitSearchText.value = matchedSuit ? `《${matchedSuit.name}》` : pendingSuitState.searchText
  window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' })
}

// 搜索下拉框相关逻辑
const selectSuit = (suit) => {
  newClothes.suit_id = suit.id
  newClothes.suit_status = suit.id ? 'existing' : ''
  suitSearchText.value = suit.id ? `《${suit.name}》` : ''
}

// 提交入库
const submitNewClothes = async () => {
  if (isSubmitting.value) return

  try {
    const successName = await executeSubmit()
    alert(`🎉 【${successName}】已汇聚多方数据并成功入库！`)
    suitSearchText.value = ''
  } catch (err) {
    alert(err.message || '提交失败，请刷新后重试。')
  }
}

const rejectSelectedPendingClothes = async () => {
  if (isSubmitting.value) return

  const pendingIds = [...new Set(newClothes.pendingIds || [])]
  if (!pendingIds.length) {
    alert('请先选择一条待审核服装申请。')
    return
  }

  const clothesName = String(newClothes.name || '当前申请').trim()
  const confirmed = confirm(`确认驳回《${clothesName}》对应的 ${pendingIds.length} 条服装申请吗？驳回后提交人可以重新申请。`)
  if (!confirmed) return

  isRejecting.value = true
  try {
    const rejectedCount = await rejectPendingItem(pendingIds)
    alert(`已驳回《${clothesName}》对应的 ${rejectedCount} 条服装申请。`)
    suitSearchText.value = ''
  } catch (err) {
    alert(err.message || '驳回失败，请刷新后重试。')
  } finally {
    isRejecting.value = false
  }
}
</script>

<template>
  <div class="admin-container pb-20 max-w-4xl mx-auto">
    <div class="flex flex-col md:flex-row justify-between items-center bg-white p-4 rounded-2xl shadow-sm mb-6 border border-slate-100">
      <div class="flex gap-2 bg-slate-50 p-1.5 rounded-xl border border-slate-100 w-full md:w-auto">
        <button @click="activeTab = 'audit'" :class="activeTab === 'audit' ? 'bg-white text-purple-600 shadow-sm' : 'text-slate-500'" class="flex-1 md:flex-none px-6 py-2 rounded-lg font-bold text-sm transition-all">👗 散件仲裁</button>
        <button @click="activeTab = 'suits'" :class="activeTab === 'suits' ? 'bg-white text-blue-600 shadow-sm' : 'text-slate-500'" class="flex-1 md:flex-none px-6 py-2 rounded-lg font-bold text-sm transition-all">📦 套装审核</button>
        <button v-if="isSuperAdminRole(currentUserRole)" @click="activeTab = 'users'" :class="activeTab === 'users' ? 'bg-white text-rose-600 shadow-sm' : 'text-slate-500'" class="flex-1 md:flex-none px-6 py-2 rounded-lg font-bold text-sm transition-all">🛡️ 权限大盘</button>
      </div>
      <button @click="emit('back-to-main')" class="mt-4 md:mt-0 text-sm font-bold text-slate-400 hover:text-slate-600 flex items-center gap-1"><span class="text-lg">🏠</span> 返回前台</button>
    </div>

    <div v-show="activeTab === 'audit'">
      <section v-if="sortedPendingList.length > 0" class="mb-8">
        <div class="mb-4 flex flex-col gap-3">
          <h3 class="text-lg font-black text-slate-800 flex items-center gap-2">🔥 自动入库申请</h3>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="option in auditFilterOptions"
              :key="option.key"
              type="button"
              @click="activeAuditFilter = option.key"
              class="rounded-full border px-3 py-1.5 text-xs font-black transition-all"
              :class="activeAuditFilter === option.key ? 'border-purple-300 bg-purple-50 text-purple-700 shadow-sm' : 'border-slate-100 bg-white text-slate-500 hover:border-purple-200 hover:text-purple-600'"
            >
              {{ option.label }} {{ option.count }}
            </button>
          </div>
        </div>
        <div v-if="displayPendingList.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-white/70 p-6 text-center text-sm font-bold text-slate-400">
          当前筛选下暂无申请。
        </div>
        <div v-else class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
          <div v-for="group in displayPendingList" :key="group.key" @click="handleClusteredItem(group)" class="bg-white border-2 border-slate-100 hover:border-purple-300 p-4 rounded-xl cursor-pointer transition-all hover:-translate-y-1 hover:shadow-md group">
            <div class="flex justify-between items-start mb-2">
              <span class="font-black text-slate-700 truncate pr-2 group-hover:text-purple-600">{{ group.name || group.items[0]?.name || '未命名散件' }}</span>
              <span class="font-black text-xs px-2 py-1 rounded-md shrink-0" :class="group.statusClass">{{ group.statusLabel }}</span>
            </div>
            <div class="text-xs font-bold text-slate-400 truncate">短编号: {{ group.items[0].game_id || 'N' }} | {{ group.items[0].category }}</div>
            <div class="mt-3 space-y-1.5 text-xs font-bold text-slate-500">
              <div class="flex items-center justify-between rounded-lg bg-slate-50 px-3 py-2">
                <span>提交人数</span>
                <span class="text-slate-800">{{ group.distinctSubmitterCount }} 人</span>
              </div>
              <div class="flex items-center justify-between rounded-lg bg-slate-50 px-3 py-2">
                <span>总提交</span>
                <span class="text-slate-800">{{ group.items.length }} 条</span>
              </div>
              <div v-if="group.hasConflict" class="flex items-center justify-between rounded-lg bg-slate-50 px-3 py-2">
                <span>最多人认可</span>
                <span class="text-slate-800">{{ group.topSubmitterCount }} 人</span>
              </div>
              <div class="flex items-center justify-between rounded-lg bg-slate-50 px-3 py-2">
                <span>资料一致情况</span>
                <span
                  :class="group.hasConflict ? 'text-amber-600' : (group.topSubmitterCount >= 5 ? 'text-emerald-600' : 'text-slate-800')"
                >
                  {{ group.hasConflict ? '有不同意见' : (group.topSubmitterCount >= 5 ? '全部一致' : '暂未足够') }}
                </span>
              </div>
            </div>
            <div class="mt-2 flex flex-wrap gap-1 text-[11px] font-bold">
              <span v-if="group.anonymousCount" class="rounded-full bg-slate-100 px-2 py-0.5 text-slate-500">匿名提交 {{ group.anonymousCount }} 条</span>
              <span v-if="group.hasKnownClothes" class="rounded-full bg-blue-50 px-2 py-0.5 text-blue-500">正式库已存在</span>
            </div>
          </div>
        </div>
      </section>

      <section id="entry-form" class="bg-white p-5 md:p-6 rounded-2xl shadow-sm border border-slate-100 border-t-4 border-t-primary mt-6">
        <div class="flex justify-between items-center mb-5 pb-4 border-b border-slate-50">
          <h3 class="text-lg md:text-xl font-black text-slate-800 m-0">👑 图鉴仲裁入库</h3>
        </div>
        
        <ClothesEntryForm 
          :form="newClothes"
          v-model:suitSearchText="suitSearchText"
          :availableSuits="suitList"
          :isSubmitting="isSubmitting"
          :submitText="auditSubmitText"
          :submitLoadingText="auditSubmitLoadingText"
          suitNotFoundText="➕ 秒建套装"
          @submit="submitNewClothes"
          @create-suit="quickCreateSuit"
        >
          <template #admin-tips>
            <div
              v-if="auditSelectionInfo"
              class="rounded-xl border px-3 py-2 text-xs font-bold leading-relaxed"
              :class="auditSelectionInfo.requiresManualReview ? 'border-rose-100 bg-rose-50 text-rose-700' : 'border-amber-100 bg-amber-50 text-amber-700'"
            >
              <template v-if="auditSelectionInfo.requiresManualReview">
                {{ auditSelectionInfo.manualReviewMessage }}
              </template>
              <template v-else-if="auditSelectionInfo.canCompleteExisting">
                本次将补全正式库已有记录《{{ auditSelectionInfo.existingClothes?.name }}》，只补空字段，不会覆盖正式库已有非空字段。
              </template>
              <template v-if="auditSelectionInfo.conflictCount">
                本次采用最多人认可的资料：{{ auditSelectionInfo.selectedSubmitterCount }} 人 / {{ auditSelectionInfo.selectedCount }} 条。
                另有不同意见的提交，暂不入库。
              </template>
              <template v-else-if="!auditSelectionInfo.requiresManualReview && !auditSelectionInfo.canCompleteExisting">
                已有 {{ auditSelectionInfo.selectedSubmitterCount }} 人提交相同资料，可入库。
              </template>
              <div v-if="auditSelectionInfo.variants?.length > 1" class="mt-2 space-y-1.5">
                <div
                  v-for="variant in auditSelectionInfo.variants"
                  :key="variant.key"
                  class="rounded-lg border bg-white/70 px-2 py-1.5"
                  :class="variant.selected ? 'border-emerald-200 text-emerald-700' : 'border-amber-100 text-amber-700'"
                >
                  <div class="flex items-center justify-between gap-2">
                    <span>{{ variant.selected ? '本次采用' : '不同意见' }}</span>
                    <span>{{ variant.submitterCount }} 人 / {{ variant.rowCount }} 条</span>
                  </div>
                  <div class="mt-1 text-[11px] font-bold text-slate-500">
                    星级 {{ variant.stars }}；{{ variant.suitLabel }}；{{ variant.tags }}
                  </div>
                  <div class="mt-0.5 text-[10px] font-bold text-slate-400">
                    pending: {{ variant.pendingIds }}
                  </div>
                </div>
              </div>
              <button
                v-if="newClothes.pendingIds.length"
                type="button"
                :disabled="isSubmitting"
                class="mt-3 w-full rounded-lg border border-rose-200 bg-white px-3 py-2 text-sm font-black text-rose-600 transition-colors hover:border-rose-300 hover:bg-rose-50 disabled:cursor-not-allowed disabled:opacity-50"
                @click="rejectSelectedPendingClothes"
              >
                {{ isRejecting ? '正在驳回...' : `驳回当前服装申请（${newClothes.pendingIds.length} 条）` }}
              </button>
            </div>
          </template>
        </ClothesEntryForm>
      </section>
    </div>

    <div v-show="activeTab === 'suits'">
      <section class="bg-white p-5 md:p-6 rounded-2xl shadow-sm border border-slate-100 border-t-4 border-t-blue-500">
        <h3 class="text-lg md:text-xl font-black text-slate-800 mb-5 pb-4 border-b border-slate-50">📦 待审核新建套装</h3>
        <div v-if="uniquePendingSuits.length === 0" class="text-center py-10 text-slate-400 font-bold">暂无需要审核的套装申请哦~</div>
        <div v-else class="space-y-3">
          <div v-for="suit in uniquePendingSuits" :key="suit.name" class="flex flex-col sm:flex-row justify-between sm:items-center bg-slate-50 border border-slate-100 p-4 rounded-xl gap-3">
            <div>
              <div class="font-black text-slate-700 text-lg flex items-center gap-2">《{{ suit.name }}》 <span class="bg-blue-100 text-blue-600 text-[10px] px-2 py-0.5 rounded">{{ suit.count }} 人申请</span></div>
              <div class="text-xs text-slate-400 font-bold mt-1">首次申请时间: {{ new Date(suit.created_at).toLocaleString() }}</div>
            </div>
            <div class="flex gap-2 shrink-0">
              <button @click="rejectPendingSuit(suit.name)" class="px-4 py-2 bg-white border border-slate-200 text-slate-500 hover:text-rose-500 hover:border-rose-200 font-bold text-sm rounded-lg transition-colors">驳回</button>
              <button @click="approvePendingSuit(suit.name)" class="px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white font-bold text-sm rounded-lg transition-colors shadow-sm shadow-blue-500/30">✅ 批准入库</button>
            </div>
          </div>
        </div>
      </section>
    </div>

    <div v-show="activeTab === 'users' && isSuperAdminRole(currentUserRole)">
      <UserManageBoard :allUsersList="allUsersList" :currentUserId="currentUserId || ''" @refresh-data="fetchAllData" />
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
