<script setup>
import { ref, computed, onBeforeUnmount, watch } from 'vue'
import { supabase } from '../api/supabase'
import { fetchMyLevelBenefits } from '../api/pointsService.js'
import { getDisplayUsername, getUserRankAndPrivilege } from '../composables/useUserPrivilege'
import UserLevelProgress from './UserLevelProgress.vue'
import LevelBenefitsPanel from './LevelBenefitsPanel.vue'
import {
  fetchMyRejectedClothingSubmissions,
  leaveCurrentAdminTerm
} from '../api/adminCapabilitiesService'

// 🌟 1. 严格的代码管理：只接收父组件传来的 profileData
const props = defineProps({
  profileData: { type: Object, default: () => ({}) },
  adminCapabilities: { type: Object, default: () => ({}) }
})
// 🌟 2. 严格的代码管理：不越级请求数据，只向父组件汇报“我要刷新数据”
const emit = defineEmits(['refresh-data', 'profile-updated'])

const localProfile = ref(null)
const displayProfile = computed(() => localProfile.value || props.profileData)
const totalPoints = ref(null)
const levelBenefits = ref(null)
const isPointsLoading = ref(false)
const pointsLoadError = ref(false)
const myRank = computed(() => (
  totalPoints.value === null ? null : getUserRankAndPrivilege(totalPoints.value)
))
const newUsername = ref('')
const isUpdatingName = ref(false)
const isModalOpen = ref(false)
const rejectedSubmissions = ref([])
let pointsRequestId = 0

watch(
  () => props.profileData,
  (profile) => {
    if (profile) localProfile.value = null
  }
)

const loadPoints = async () => {
  const requestId = ++pointsRequestId

  if (!props.profileData?.id) {
    totalPoints.value = null
    levelBenefits.value = null
    isPointsLoading.value = false
    pointsLoadError.value = false
    return
  }

  isPointsLoading.value = true
  pointsLoadError.value = false

  try {
    const benefits = await fetchMyLevelBenefits(supabase)
    if (requestId !== pointsRequestId) return
    levelBenefits.value = benefits
    totalPoints.value = benefits.totalPoints
  } catch (error) {
    if (requestId !== pointsRequestId) return
    console.error('获取当前用户积分汇总失败:', error)
    totalPoints.value = null
    levelBenefits.value = null
    pointsLoadError.value = true
  } finally {
    if (requestId === pointsRequestId) isPointsLoading.value = false
  }
}

const loadRejectedSubmissions = async () => {
  if (!props.profileData?.id) {
    rejectedSubmissions.value = []
    return
  }
  try {
    rejectedSubmissions.value = await fetchMyRejectedClothingSubmissions()
  } catch (error) {
    console.error('获取驳回原因失败:', error)
    rejectedSubmissions.value = []
  }
}

const leaveAdminTerm = async () => {
  if (!window.confirm('确认退出当前普通管理员任期吗？退出后系统会按月初候选顺序补位。')) return
  try {
    await leaveCurrentAdminTerm()
    emit('refresh-data')
  } catch (error) {
    window.alert(error.message || '退出任期失败')
  }
}

watch(() => props.profileData?.id, loadPoints, { immediate: true })
watch(() => props.profileData?.id, loadRejectedSubmissions, { immediate: true })
onBeforeUnmount(() => { pointsRequestId++ })

const updateUsername = async () => {
  const cleanName = newUsername.value.trim()
  if (!cleanName) return alert('用户名不能为空！')
  if (cleanName.startsWith('匿名搭配师_')) return alert('不能使用系统保留的匿名格式哦！')

  isUpdatingName.value = true
  try {
    const { data, error } = await supabase.rpc('update_profile_username', {
      p_username: cleanName
    })

    if (error) {
      if (error.code === '23505') throw new Error(`代号 "${cleanName}" 已被抢注，换一个霸气点的名字吧！`)
      throw error
    }

    if (!data) throw new Error('代号没有保存成功，请稍后重试')

    const updatedProfile = Array.isArray(data) ? data[0] : data
    localProfile.value = { ...props.profileData, ...updatedProfile }
    
    alert('🎉 代号修改成功！')
    newUsername.value = ''
    isModalOpen.value = false 
    
    emit('profile-updated', localProfile.value)
    emit('refresh-data')
    
  } catch (err) {
    alert('❌ 修改失败：' + err.message)
  } finally {
    isUpdatingName.value = false
  }
}

const openEditModal = () => {
  newUsername.value = displayProfile.value?.username || ''
  isModalOpen.value = true
}
</script>

<template>
  <div class="space-y-6" v-if="displayProfile">
    <section v-if="adminCapabilities.term_id" class="rounded-2xl border border-purple-100 bg-purple-50 p-5 shadow-sm">
      <div class="flex flex-col justify-between gap-3 md:flex-row md:items-center">
        <div>
          <h3 class="font-black text-purple-900">当前普通管理员任期</h3>
          <p class="mt-1 text-sm font-bold text-purple-700">
            {{ adminCapabilities.term_source === 'monthly' ? '月度轮值' : (adminCapabilities.term_source === 'manual' ? '手动授予' : '旧管理员过渡') }}
            · 至 {{ new Date(adminCapabilities.term_ends_at).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }) }}
          </p>
        </div>
        <button class="rounded-lg border border-purple-200 bg-white px-3 py-2 text-xs font-black text-purple-700" @click="leaveAdminTerm">退出任期</button>
      </div>
    </section>

    <section v-if="rejectedSubmissions.length" class="rounded-2xl border border-amber-100 bg-amber-50 p-5 shadow-sm">
      <h3 class="font-black text-amber-900">需要重新提交的服装资料</h3>
      <p class="mt-1 text-xs font-bold text-amber-700">以下申请已被可逆驳回。请按原因修正后，从录入入口重新提交；历史记录不会删除。</p>
      <div class="mt-4 space-y-3">
        <article v-for="item in rejectedSubmissions" :key="item.pending_id" class="rounded-xl bg-white p-4">
          <div class="font-black text-slate-800">{{ item.name || '未命名服装' }} · {{ item.category }} · {{ item.game_id }}</div>
          <div class="mt-1 text-sm font-bold text-rose-600">驳回原因：{{ item.reason }}</div>
        </article>
      </div>
    </section>
    <section class="bg-white rounded-2xl p-6 shadow-sm border border-slate-100 relative overflow-hidden">
      <div class="absolute top-0 left-0 w-full h-1.5 bg-gradient-to-r from-pink-400 to-purple-500"></div>
      <h3 class="text-lg font-black text-slate-800 mb-6 flex items-center gap-2">
        <span>✨</span> 我的搭配师档案
      </h3>
      
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="p-4 rounded-xl bg-slate-50 border border-slate-100 relative group">
          <div class="flex justify-between items-center mb-1">
            <span class="text-xs font-bold text-slate-400">当前代号</span>
            <button @click="openEditModal" class="text-xs font-bold text-pink-500 bg-pink-50 px-2 py-1 rounded-md hover:bg-pink-500 hover:text-white transition-colors cursor-pointer">
              ✏️ 修改
            </button>
          </div>
          <div class="text-lg font-black text-pink-500 truncate">{{ getDisplayUsername(displayProfile) }}</div>
          <div v-if="!displayProfile.username" class="mt-1 text-[10px] font-bold text-rose-500 bg-rose-50 px-2 py-0.5 rounded w-fit">尚未设置专属代号</div>
        </div>
        
        <div class="p-4 rounded-xl bg-slate-50 border border-slate-100">
          <div class="text-xs font-bold text-slate-400 mb-1">社区头衔</div>
          <div v-if="isPointsLoading" class="text-lg font-black text-slate-400">正在计算…</div>
          <div v-else-if="pointsLoadError" class="text-lg font-black text-slate-400">暂不可用</div>
          <template v-else>
            <div class="text-lg font-black text-slate-700">{{ myRank?.title }}</div>
            <div class="mt-1 text-[11px] font-bold text-slate-500">陪审票权：{{ levelBenefits?.voteWeight ?? myRank?.voteWeight ?? 1 }} 票；有效业务奖励额外 +{{ levelBenefits?.bonusPerEvent ?? myRank?.bonusPoints ?? 0 }} 分</div>
          </template>
        </div>
        
        <div class="p-4 rounded-xl bg-slate-50 border border-slate-100" aria-live="polite">
          <div class="text-xs font-bold text-slate-400 mb-1">累计积分</div>
          <div v-if="isPointsLoading" class="text-lg font-black text-slate-400">读取中…</div>
          <template v-else-if="pointsLoadError">
            <div class="text-sm font-black text-rose-500">积分暂时无法读取</div>
            <button type="button" class="mt-2 text-[11px] font-bold text-purple-600 hover:text-purple-800 cursor-pointer" @click="loadPoints">
              重新读取
            </button>
          </template>
          <template v-else>
            <div class="text-lg font-black text-purple-600">{{ totalPoints }} 分</div>
            <div class="mt-1 text-[11px] font-bold text-slate-500">来自积分流水汇总</div>
          </template>
        </div>
      </div>

      <UserLevelProgress v-if="totalPoints !== null" :total-points="totalPoints" />
      <LevelBenefitsPanel v-if="levelBenefits" :benefits="levelBenefits" />
    </section>

    <Teleport to="body">
      <div v-if="isModalOpen" class="modal-overlay" @click.self="isModalOpen = false">
        <div class="modal-content">
          <button @click="isModalOpen = false" class="close-btn">✕</button>
          
          <h3 class="text-lg font-black text-slate-800 mb-2 flex items-center gap-2">
            <span>🏷️</span> 设置专属代号
          </h3>
          <p class="text-xs font-bold text-slate-400 mb-6 leading-relaxed">代号具有全站唯一性，设置后将展示在您的图鉴贡献榜中。</p>
          
          <div class="flex flex-col gap-4">
            <input 
              type="text" 
              v-model="newUsername" 
              placeholder="输入新昵称 (不可重复)" 
              class="custom-input" 
              @keyup.enter="updateUsername"
            />
            <button @click="updateUsername" :disabled="isUpdatingName" class="btn-primary">
              {{ isUpdatingName ? '保存中...' : '确认修改' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0, 0, 0, 0.4); display: flex; align-items: center; justify-content: center; z-index: 9999; backdrop-filter: blur(4px); }
.modal-content { background: white; padding: 30px; border-radius: 24px; width: 90%; max-width: 400px; position: relative; box-shadow: 0 20px 50px rgba(0, 0, 0, 0.15); animation: popIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275); }
.close-btn { position: absolute; top: 16px; right: 16px; color: #94a3b8; font-weight: bold; font-size: 16px; cursor: pointer; background: none; border: none; transition: 0.2s; }
.close-btn:hover { color: #1e293b; transform: scale(1.1); }
.custom-input { width: 100%; padding: 14px; border: 2px solid #f1f5f9; border-radius: 12px; font-size: 14px; font-weight: bold; outline: none; transition: 0.2s; background: #f8fafc; color: #1e293b; }
.custom-input:focus { border-color: #f472b6; background: white; box-shadow: 0 0 0 3px rgba(244, 114, 182, 0.1); }
.btn-primary { width: 100%; padding: 14px; border-radius: 12px; background: linear-gradient(135deg, #f472b6 0%, #d946ef 100%); color: white; border: none; font-weight: 900; font-size: 15px; cursor: pointer; transition: 0.2s; box-shadow: 0 4px 15px rgba(244, 114, 182, 0.3); }
.btn-primary:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(244, 114, 182, 0.4); }
.btn-primary:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
@keyframes popIn { 0% { opacity: 0; transform: scale(0.95) translateY(10px); } 100% { opacity: 1; transform: scale(1) translateY(0); } }
</style>
