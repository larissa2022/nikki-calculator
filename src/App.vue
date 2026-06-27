<script setup>
import { ref, onMounted, watch } from 'vue'
import { useAuth } from './composables/useAuth'
import { useWardrobe } from './composables/useWardrobe'
import { supabase } from './api/supabase'

import AuthModal from './components/AuthModal.vue'
import MainView from './views/MainView.vue'
import AdminView from './views/AdminView.vue'

// 🌟 1. 核心修复：在这里把 userProfile 提取出来
const { currentUser, userProfile, isAdmin, userQuota, initAuth, fetchProfile } = useAuth()
const { fullWardrobeData, myWardrobeIds, stagesData, isLoading, loadData, syncWardrobeFromCloud, saveWardrobeToCloud } = useWardrobe()

const currentMode = ref('main') 
const isAuthModalOpen = ref(false)

watch(currentUser, (newUser) => {
  if (newUser) syncWardrobeFromCloud(newUser.id)
  else myWardrobeIds.value = []
})

onMounted(async () => {
  await loadData()
  await initAuth()
  
  supabase.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT') {
      currentUser.value = null 
    } 
  })
})

const handleSaveCloud = async () => {
  try {
    await saveWardrobeToCloud(currentUser.value?.id)
    alert('🎉 录入成功！数据已同步至云端。')
  } catch (err) {
    alert('❌ 保存失败：' + err.message)
  }
}

const handleRefreshCatalog = async () => {
  await loadData({ force: true })
  if (currentUser.value) {
    await syncWardrobeFromCloud(currentUser.value.id)
  }
}
</script>

<template>
  <div class="root-wrapper">
    <AuthModal v-if="isAuthModalOpen" @close="isAuthModalOpen = false" />
    
    <AdminView 
      v-if="currentMode === 'admin' && isAdmin" 
      :fullWardrobeData="fullWardrobeData"
      @back-to-main="currentMode = 'main'" 
    />

    <MainView 
      v-else
      :currentUser="currentUser"
      :userProfile="userProfile" 
      :isAdmin="isAdmin"
      :userQuota="userQuota"
      :fullWardrobeData="fullWardrobeData"
      :myWardrobeIds="myWardrobeIds"
      :stagesData="stagesData"
      :isLoading="isLoading"
      @open-login="isAuthModalOpen = true"
      @go-admin="currentMode = 'admin'"
      @update:ownedIds="myWardrobeIds = $event"
      @save-cloud="handleSaveCloud"
      @refresh-profile="fetchProfile"
      @refresh-catalog="handleRefreshCatalog"
    />
    </div>
</template>

<style>
/* 🌟 这里只保留全局底色和最基础的排版 */
body { margin: 0; padding: 0; font-family: 'PingFang SC', 'Microsoft YaHei', sans-serif; background-color: #fdf2f8; background-image: radial-gradient(#fbcfe8 1px, transparent 1px); background-size: 20px 20px; color: #333; }
.root-wrapper { display: flex; justify-content: center; min-height: 100vh; padding: 20px; box-sizing: border-box; }
.app-container { width: 100%; max-width: 680px; background: rgba(255, 255, 255, 0.85); backdrop-filter: blur(12px); border-radius: 24px; box-shadow: 0 10px 30px rgba(219, 39, 119, 0.1); border: 1px solid rgba(255,255,255,0.6); padding: 30px; margin: 0 auto; box-sizing: border-box; }

@media (max-width: 768px) {
  .root-wrapper { padding: 10px; }
  .app-container { padding: 15px; border-radius: 16px; }
}
</style>
