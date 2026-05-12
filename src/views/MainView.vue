<script setup>
import { ref } from 'vue'
import AuthBar from '../components/AuthBar.vue'
import Calculator from '../components/Calculator.vue'
import ImportZone from '../components/ImportZone.vue'
import WardrobeGrid from '../components/WardrobeGrid.vue'
import SuitGallery from '../components/SuitGallery.vue'

// 接收来自大总管 App.vue 的数据
const props = defineProps({
  currentUser: Object, isAdmin: Boolean, userQuota: Number,
  fullWardrobeData: Array, myWardrobeIds: Array, stagesData: Array, isLoading: Boolean
})

// 向大总管 App.vue 汇报的事件
const emit = defineEmits(['open-login', 'go-admin', 'update:ownedIds', 'save-cloud', 'refresh-profile'])

const currentTab = ref('calculator')
</script>

<template>
  <div class="app-container">
    <AuthBar :user="currentUser" @open-login="emit('open-login')" />

    <header>
      <h1>✨ 奇迹暖暖极速搭配器 ✨</h1>
      <nav class="tabs">
        <button :class="{ active: currentTab === 'calculator' }" @click="currentTab = 'calculator'">搭配计算</button>
        <button :class="{ active: currentTab === 'import' }" @click="currentTab = 'import'">录入衣柜</button>
        <button :class="{ active: currentTab === 'wardrobe' }" @click="currentTab = 'wardrobe'">我的衣柜</button>
        <button :class="{ active: currentTab === 'suits' }" @click="currentTab = 'suits'">套装图鉴</button>
        <button v-if="isAdmin" :class="{ active: currentTab === 'admin' }" @click="emit('go-admin')" class="admin-tab-btn">图鉴管理</button>
      </nav>
    </header>

    <div v-if="isLoading" class="loading-state"><h2>⏳ 奇迹载入中...</h2></div>
    
    <main v-else>
      <Calculator v-if="currentTab === 'calculator'" :wardrobe="fullWardrobeData" :ownedIds="myWardrobeIds" :stages="stagesData" />
      <ImportZone v-if="currentTab === 'import'" :wardrobe="fullWardrobeData" :ownedIds="myWardrobeIds" :quota="userQuota" :isLoggedIn="!!currentUser" @update:ownedIds="emit('update:ownedIds', $event)" @save-cloud="emit('save-cloud')" @refresh-profile="emit('refresh-profile')" />
      <WardrobeGrid v-if="currentTab === 'wardrobe'" :wardrobe="fullWardrobeData" :ownedIds="myWardrobeIds" :isLoggedIn="!!currentUser" @update:ownedIds="emit('update:ownedIds', $event)" @save-cloud="emit('save-cloud')" />
      <SuitGallery v-if="currentTab === 'suits'" :wardrobe="fullWardrobeData" :ownedIds="myWardrobeIds" :isLoggedIn="!!currentUser" @update:ownedIds="emit('update:ownedIds', $event)" @save-cloud="emit('save-cloud')" />
    </main>
  </div>
</template>

<style scoped>
/* 这里原本在 App.vue 里关于导航栏的样式，以后就归 MainView 管了 */
header { text-align: center; margin-bottom: 25px; animation: slideDown 0.5s ease-out; }
h1 { color: #f472b6; font-size: 24px; margin-bottom: 20px; font-weight: 900; letter-spacing: 1px; text-shadow: 0 2px 4px rgba(244, 114, 182, 0.2); }
.tabs { display: flex; justify-content: center; gap: 10px; flex-wrap: wrap; }
.tabs button { background: rgba(255, 255, 255, 0.6); border: 2px solid #fbcfe8; padding: 10px 18px; border-radius: 12px; cursor: pointer; font-size: 14px; font-weight: bold; color: #db2777; transition: all 0.3s; }
.tabs button.active { background: linear-gradient(135deg, #f472b6 0%, #d946ef 100%); color: white; border-color: transparent; box-shadow: 0 4px 15px rgba(244, 114, 182, 0.3); transform: translateY(-2px); }
.tabs button:hover:not(.active) { background: #fdf2f8; transform: translateY(-1px); }
.admin-tab-btn { background: #f3e8ff !important; border-color: #d8b4fe !important; color: #9333ea !important; }
.admin-tab-btn.active { background: linear-gradient(135deg, #a855f7 0%, #7c3aed 100%) !important; color: white !important; }
.loading-state { text-align: center; padding: 50px 0; color: #f472b6; }
@keyframes slideDown { from { opacity: 0; transform: translateY(-20px); } to { opacity: 1; transform: translateY(0); } }
</style>