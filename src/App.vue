<script setup>
import { ref, onMounted, watch } from 'vue' // 🌟 新增了 watch
import { useAuth } from './composables/useAuth'
import { useWardrobe } from './composables/useWardrobe'

// 引入模块化组件
import AuthBar from './components/AuthBar.vue'
import AuthModal from './components/AuthModal.vue'
import Calculator from './components/Calculator.vue'
import ImportZone from './components/ImportZone.vue'
import WardrobeGrid from './components/WardrobeGrid.vue'
import AdminPanel from './components/AdminPanel.vue'
import SuitGallery from './components/SuitGallery.vue'


// 逻辑分发中心
const { currentUser, isAdmin, userQuota, initAuth, fetchProfile } = useAuth()
const { fullWardrobeData, myWardrobeIds, stagesData, isLoading, loadData, syncWardrobeFromCloud, saveWardrobeToCloud } = useWardrobe()

// 视图控制状态
const currentTab = ref('calculator')
const isAuthModalOpen = ref(false)

// 🌟 新增：监控用户状态，自动处理数据清理与同步
watch(currentUser, (newUser) => {
  if (newUser) {
    // 监听到有新用户登录，立刻拉取他的云端衣柜
    syncWardrobeFromCloud(newUser.id)
  } else {
    // 监听到用户登出 (变为 null)，立刻清空本地衣柜！
    myWardrobeIds.value = []
  }
})

// 应用总启动
onMounted(async () => {
  await loadData()
  await initAuth()
  // ✂️ 这里原来那三行关于 syncWardrobeFromCloud 的代码可以直接删掉了，
  // 因为上面的 watch 已经完美接管了登录后的同步工作！
})
</script>

<template>
  <div class="app-container">
    
    <AuthBar :user="currentUser" @open-login="isAuthModalOpen = true" />
    
    <AuthModal v-if="isAuthModalOpen" @close="isAuthModalOpen = false" />

    <header>
      <h1>✨ 奇迹暖暖极速搭配器 ✨</h1>
      <nav class="tabs">
        <button :class="{ active: currentTab === 'calculator' }" @click="currentTab = 'calculator'">搭配计算</button>
        <button :class="{ active: currentTab === 'import' }" @click="currentTab = 'import'">录入衣柜</button>
        <button :class="{ active: currentTab === 'wardrobe' }" @click="currentTab = 'wardrobe'">我的衣柜</button>
        <button :class="{ active: currentTab === 'suits' }" @click="currentTab = 'suits'">套装图鉴</button>
        <button v-if="isAdmin" :class="{ active: currentTab === 'admin' }" @click="currentTab = 'admin'" class="admin-tab-btn">图鉴管理</button>
      </nav>
    </header>

    <div v-if="isLoading" class="loading-state"><h2>⏳ 奇迹载入中...</h2></div>
    
    <main v-else>
      <Calculator 
        v-if="currentTab === 'calculator'" 
        :wardrobe="fullWardrobeData" 
        :ownedIds="myWardrobeIds" 
        :stages="stagesData"
      />
      
      <ImportZone 
        v-if="currentTab === 'import'" 
        :wardrobe="fullWardrobeData"
        :ownedIds="myWardrobeIds"
        :quota="userQuota"
        :isLoggedIn="!!currentUser"
        @update:ownedIds="myWardrobeIds = $event"
        @save-cloud="saveWardrobeToCloud(currentUser?.id)"
        @refresh-profile="fetchProfile"
      />

      <WardrobeGrid 
        v-if="currentTab === 'wardrobe'" 
        :wardrobe="fullWardrobeData"
        :ownedIds="myWardrobeIds"
        :isLoggedIn="!!currentUser"
        @update:ownedIds="myWardrobeIds = $event"
        @save-cloud="saveWardrobeToCloud(currentUser?.id)"
      />

      <SuitGallery 
        v-if="currentTab === 'suits'" 
        :wardrobe="fullWardrobeData"
        :ownedIds="myWardrobeIds"
        :isLoggedIn="!!currentUser"
        @update:ownedIds="myWardrobeIds = $event"
        @save-cloud="saveWardrobeToCloud(currentUser?.id)"
      />

      <AdminPanel 
        v-if="currentTab === 'admin' && isAdmin" 
        :fullWardrobeData="fullWardrobeData"
      />
    </main>
    
  </div>
</template>