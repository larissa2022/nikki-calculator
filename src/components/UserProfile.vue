<script setup>
import { ref, computed } from 'vue'
import { supabase } from '../api/supabase'
import { getDisplayUsername, getUserRankAndPrivilege } from '../composables/useUserPrivilege'

const props = defineProps({
  currentUserInfo: { type: Object, required: true }
})
const emit = defineEmits(['refresh-data']) 

const myRank = computed(() => getUserRankAndPrivilege(props.currentUserInfo?.total_points || 0))
const newUsername = ref('')
const isUpdatingName = ref(false)

const updateUsername = async () => {
  const cleanName = newUsername.value.trim()
  if (!cleanName) return alert('用户名不能为空！')
  if (cleanName.startsWith('匿名搭配师_')) return alert('不能使用系统保留的匿名格式哦！')

  isUpdatingName.value = true
  try {
    const { error } = await supabase.from('profiles').update({ username: cleanName }).eq('id', props.currentUserInfo.id)
    if (error) {
      if (error.code === '23505') throw new Error(`代号 "${cleanName}" 已被抢注！`)
      throw error
    }
    alert('🎉 专属代号修改成功！')
    newUsername.value = ''
    emit('refresh-data') 
  } catch (err) { alert('❌ 修改失败：' + err.message) } 
  finally { isUpdatingName.value = false }
}
</script>

<template>
  <div class="space-y-6 max-w-4xl mx-auto">
    <section class="bg-white rounded-2xl p-6 shadow-sm border border-slate-100 relative overflow-hidden">
      <div class="absolute top-0 left-0 w-full h-1.5 bg-gradient-to-r from-pink-400 to-purple-500"></div>
      <h3 class="text-lg font-black text-slate-800 mb-6 flex items-center gap-2">
        <span>✨</span> 我的搭配师档案
      </h3>
      
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="p-4 rounded-xl bg-slate-50 border border-slate-100">
          <div class="text-xs font-bold text-slate-400 mb-1">当前代号</div>
          <div class="text-lg font-black text-pink-500 truncate">{{ getDisplayUsername(currentUserInfo) }}</div>
          <div v-if="!currentUserInfo?.username" class="mt-1 text-[10px] font-bold text-rose-500 bg-rose-50 px-2 py-0.5 rounded w-fit">尚未设置专属代号</div>
        </div>
        
        <div class="p-4 rounded-xl bg-slate-50 border border-slate-100">
          <div class="text-xs font-bold text-slate-400 mb-1">社区头衔</div>
          <div class="text-lg font-black text-slate-700">{{ myRank.title }}</div>
          <div class="mt-1 text-[11px] font-bold text-slate-500">投票权重: 1 顶 <span class="text-purple-500">{{ myRank.voteWeight }}</span> 票</div>
        </div>
        
        <div class="p-4 rounded-xl bg-slate-50 border border-slate-100">
          <div class="text-xs font-bold text-slate-400 mb-1">累计积分</div>
          <div class="text-lg font-black text-purple-600">{{ currentUserInfo?.total_points || 0 }} 分</div>
          <div class="mt-1 text-[11px] font-bold text-slate-500">本月活跃度: {{ currentUserInfo?.monthly_action_count || 0 }} 次</div>
        </div>
      </div>
    </section>

    <section class="bg-white rounded-2xl p-6 shadow-sm border border-slate-100">
      <h3 class="text-base font-black text-slate-800 mb-2 flex items-center gap-2">
        <span>🏷️</span> 设置专属代号
      </h3>
      <p class="text-xs font-bold text-slate-400 mb-4">代号具有全站唯一性，设置后将展示在您的图鉴贡献榜中。</p>
      
      <div class="flex flex-col sm:flex-row gap-3 max-w-md">
        <input type="text" v-model="newUsername" placeholder="输入新昵称 (不可重复)" class="input input-bordered w-full font-bold bg-slate-50 focus:bg-white focus:border-pink-400" />
        <button @click="updateUsername" :disabled="isUpdatingName" class="btn btn-primary font-black shadow-sm shrink-0">
          {{ isUpdatingName ? '保存中...' : '确认修改' }}
        </button>
      </div>
    </section>
  </div>
</template>