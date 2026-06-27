<script setup>
import { ref, computed, watch } from 'vue'
import { supabase } from '../api/supabase'
import { getDisplayUsername, getUserRankAndPrivilege } from '../composables/useUserPrivilege'

// 🌟 1. 严格的代码管理：只接收父组件传来的 profileData
const props = defineProps({
  profileData: { type: Object, default: () => ({}) }
})
// 🌟 2. 严格的代码管理：不越级请求数据，只向父组件汇报“我要刷新数据”
const emit = defineEmits(['refresh-data', 'profile-updated'])

const localProfile = ref(null)
const displayProfile = computed(() => localProfile.value || props.profileData)
const myRank = computed(() => getUserRankAndPrivilege(displayProfile.value?.total_points || 0))
const newUsername = ref('')
const isUpdatingName = ref(false)
const isModalOpen = ref(false)

watch(
  () => props.profileData,
  (profile) => {
    if (profile) localProfile.value = null
  }
)

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
          <div class="text-lg font-black text-slate-700">{{ myRank.title }}</div>
          <div class="mt-1 text-[11px] font-bold text-slate-500">投票权重: 1 顶 <span class="text-purple-500">{{ myRank.voteWeight }}</span> 票</div>
        </div>
        
        <div class="p-4 rounded-xl bg-slate-50 border border-slate-100">
          <div class="text-xs font-bold text-slate-400 mb-1">累计积分</div>
          <div class="text-lg font-black text-purple-600">{{ displayProfile.total_points || 0 }} 分</div>
          <div class="mt-1 text-[11px] font-bold text-slate-500">本月活跃度: {{ displayProfile.monthly_action_count || 0 }} 次</div>
        </div>
      </div>
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
