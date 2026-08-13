<script setup>
import { ref, watch } from 'vue'
import AuthBar from '../components/AuthBar.vue'
import Calculator from '../components/Calculator.vue'
import ImportZone from '../components/ImportZone.vue'
import WardrobeGrid from '../components/WardrobeGrid.vue'
import SuitGallery from '../components/SuitGallery.vue'
import ContributorGallery from '../components/ContributorGallery.vue'
import PointsLeaderboard from '../components/PointsLeaderboard.vue'
import CorrectionRequestBoard from '../components/CorrectionRequestBoard.vue'
import JuryReviewBoard from '../components/JuryReviewBoard.vue'
import UserProfile from '../components/UserProfile.vue'
import AboutProject from '../components/AboutProject.vue'
import DonationSupport from '../components/DonationSupport.vue'
import HomepageMonthlyThanks from '../components/HomepageMonthlyThanks.vue'
import FeatureRequestBoard from '../components/FeatureRequestBoard.vue'
import { normalizeMainTabForSession, readMainTab, writeMainTab } from '../utils/navigationState'

const props = defineProps({
  currentUser: Object,
  authInitialized: Boolean,
  userProfile: Object, // 🌟 接收全局档案数据
  isAdmin: Boolean, 
  adminCapabilities: { type: Object, default: () => ({}) },
  userQuota: Number,
  fullWardrobeData: Array, 
  myWardrobeIds: Array, 
  wardrobeSyncStatus: { type: String, default: 'idle' },
  stagesData: Array, 
  isLoading: Boolean,
  loadingDebugMessage: String,
  cloudSaveNotice: Object
})

const emit = defineEmits(['open-login', 'go-admin', 'update:ownedIds', 'save-cloud', 'refresh-profile', 'profile-updated', 'refresh-catalog', 'retry-wardrobe'])
const currentTab = ref(normalizeMainTabForSession(
  readMainTab(),
  Boolean(props.currentUser),
  props.authInitialized
))

const switchTab = (tab) => {
  const nextTab = writeMainTab(tab)
  currentTab.value = nextTab
  if (nextTab === 'suits') emit('refresh-catalog')
}

const handleSignedOut = () => {
  const nextTab = normalizeMainTabForSession(currentTab.value, false)
  if (nextTab !== currentTab.value) switchTab(nextTab)
}

watch(
  [() => props.currentUser, () => props.authInitialized],
  ([currentUser, authInitialized]) => {
    if (authInitialized && !currentUser) handleSignedOut()
  }
)
</script>

<template>
  <div class="app-container">
    <AuthBar 
      :user="currentUser" 
      :profile="userProfile" 
      @open-login="emit('open-login')" 
      @open-profile="switchTab('profile')"
      @signed-out="handleSignedOut"
    />

    <div v-if="adminCapabilities.show_grant_notice" class="mb-4 rounded-xl border border-purple-200 bg-purple-50 p-4 text-sm font-black text-purple-800" role="status">
      {{ adminCapabilities.term_source === 'monthly' ? '您已自动获得本期受限管理员权限' : (adminCapabilities.term_source === 'legacy_transition' ? '您的旧管理员权限已转换为本期受限任期' : '您已获得本期受限管理员权限') }}，可在“图鉴管理”中处理新增服装多数审核。
    </div>

    <header>
      <h1>✨ 奇迹暖暖极速搭配器 ✨</h1>
      <nav class="tabs">
        <button :class="{ active: currentTab === 'calculator' }" @click="switchTab('calculator')">搭配计算</button>
        <button :class="{ active: currentTab === 'import' }" @click="switchTab('import')">录入衣柜</button>
        <button :class="{ active: currentTab === 'wardrobe' }" @click="switchTab('wardrobe')">我的衣柜</button>
        <button :class="{ active: currentTab === 'suits' }" @click="switchTab('suits')">套装图鉴</button>
        <button :class="{ active: currentTab === 'contributors' }" @click="switchTab('contributors')">贡献名录</button>
        <button :class="{ active: currentTab === 'suggestions' }" @click="switchTab('suggestions')">优化建议</button>
        <button v-if="currentUser" :class="{ active: currentTab === 'leaderboard' }" @click="switchTab('leaderboard')">积分排行</button>
        <button v-if="currentUser" :class="{ active: currentTab === 'corrections' }" @click="switchTab('corrections')">图鉴报错</button>
        <button v-if="currentUser" :class="{ active: currentTab === 'jury' }" @click="switchTab('jury')">陪审团</button>
        <button v-if="isAdmin" :class="{ active: currentTab === 'admin' }" @click="emit('go-admin')" class="admin-tab-btn">图鉴管理</button>
      </nav>
    </header>

    <div v-if="isLoading" class="loading-state" role="status">
      <strong>⏳ 图鉴正在后台更新，页面仍可正常切换</strong>
      <p v-if="loadingDebugMessage" class="debug-loading-message">诊断：{{ loadingDebugMessage }}</p>
    </div>

    <div
      v-if="cloudSaveNotice"
      class="cloud-save-notice"
      :class="`cloud-save-notice--${cloudSaveNotice.type}`"
      role="status"
    >
      {{ cloudSaveNotice.message }}
    </div>
    
    <main>
      <HomepageMonthlyThanks v-if="currentTab === 'calculator'" />
      <Calculator
        v-if="currentTab === 'calculator'"
        :wardrobe="fullWardrobeData"
        :ownedIds="myWardrobeIds"
        :stages="stagesData"
        :isLoggedIn="Boolean(currentUser)"
        :isAuthInitialized="authInitialized"
        :wardrobeStatus="wardrobeSyncStatus"
        @open-import="switchTab('import')"
        @retry-wardrobe="emit('retry-wardrobe')"
      />
      <ImportZone v-if="currentTab === 'import'" :key="currentUser?.id || 'guest'" :wardrobe="fullWardrobeData" :ownedIds="myWardrobeIds" :quota="userQuota" :isLoggedIn="!!currentUser" :userId="currentUser?.id || ''" @update:ownedIds="emit('update:ownedIds', $event)" @save-cloud="emit('save-cloud', $event)" @refresh-profile="emit('refresh-profile')" />
      <WardrobeGrid v-if="currentTab === 'wardrobe'" :wardrobe="fullWardrobeData" :ownedIds="myWardrobeIds" :isLoggedIn="!!currentUser" @update:ownedIds="emit('update:ownedIds', $event)" @save-cloud="emit('save-cloud')" />
      <SuitGallery v-if="currentTab === 'suits'" :wardrobe="fullWardrobeData" :ownedIds="myWardrobeIds" :isLoggedIn="!!currentUser" @update:ownedIds="emit('update:ownedIds', $event)" @save-cloud="emit('save-cloud', $event)" @refresh-catalog="emit('refresh-catalog')" />
      <ContributorGallery v-if="currentTab === 'contributors'" :wardrobe="fullWardrobeData" />
      <FeatureRequestBoard
        v-if="currentTab === 'suggestions'"
        :key="currentUser?.id || 'guest'"
        :is-logged-in="Boolean(currentUser)"
        :user-id="currentUser?.id || ''"
      />
      <PointsLeaderboard
        v-if="currentTab === 'leaderboard'"
        :key="currentUser?.id || 'guest'"
      />
      <CorrectionRequestBoard
        v-if="currentTab === 'corrections'"
        :key="currentUser?.id || 'guest'"
        :isLoggedIn="Boolean(currentUser)"
        :userId="currentUser?.id || ''"
        :wardrobe="fullWardrobeData"
      />
      <JuryReviewBoard
        v-if="currentTab === 'jury'"
        :isLoggedIn="Boolean(currentUser)"
        :isSuperAdmin="adminCapabilities.is_super_admin === true"
      />
      
      <UserProfile 
        v-if="currentTab === 'profile'" 
        :profileData="userProfile" 
        :adminCapabilities="adminCapabilities"
        @refresh-data="emit('refresh-profile')" 
        @profile-updated="emit('profile-updated', $event)"
      />
      <AboutProject v-if="currentTab === 'about'" @open-donate="switchTab('donate')" />
      <DonationSupport v-if="currentTab === 'donate'" />
    </main>

    <footer class="site-footer">
      <span>奇迹暖暖极速搭配器将继续免费使用</span>
      <nav aria-label="项目说明">
        <button type="button" @click="switchTab('about')">关于项目</button>
        <button type="button" @click="switchTab('donate')">打赏</button>
      </nav>
    </footer>
  </div>
</template>

<style scoped>
/* 这里原本在 App.vue 里关于导航栏的样式，以后就归 MainView 管了 */
header { text-align: center; margin-bottom: 25px; animation: slideDown 0.5s ease-out; }
h1 { color: #f472b6; font-size: 24px; margin-bottom: 20px; font-weight: 900; letter-spacing: 1px; text-shadow: 0 2px 4px rgba(244, 114, 182, 0.2); }
.tabs { display: flex; justify-content: center; gap: 10px; flex-wrap: wrap; }
.site-footer { display: flex; align-items: center; justify-content: space-between; gap: 14px; margin-top: 28px; padding: 16px 4px 4px; border-top: 1px solid #f1f5f9; color: #94a3b8; font-size: 10px; font-weight: 700; }
.site-footer nav { display: flex; gap: 8px; }
.site-footer button { border: 0; background: transparent; color: #7c3aed; font-size: 11px; font-weight: 900; cursor: pointer; }
.site-footer button:hover { color: #db2777; }
@media (max-width: 540px) { .site-footer { align-items: flex-start; flex-direction: column; } }
.tabs button { background: rgba(255, 255, 255, 0.6); border: 2px solid #fbcfe8; padding: 10px 18px; border-radius: 12px; cursor: pointer; font-size: 14px; font-weight: bold; color: #db2777; transition: all 0.3s; }
.tabs button.active { background: linear-gradient(135deg, #f472b6 0%, #d946ef 100%); color: white; border-color: transparent; box-shadow: 0 4px 15px rgba(244, 114, 182, 0.3); transform: translateY(-2px); }
.tabs button:hover:not(.active) { background: #fdf2f8; transform: translateY(-1px); }
.admin-tab-btn { background: #f3e8ff !important; border-color: #d8b4fe !important; color: #9333ea !important; }
.admin-tab-btn.active { background: linear-gradient(135deg, #a855f7 0%, #7c3aed 100%) !important; color: white !important; }
.loading-state { margin-bottom: 14px; padding: 10px 12px; border: 1px solid #fbcfe8; border-radius: 12px; background: #fdf2f8; color: #be185d; font-size: 12px; text-align: center; }
.cloud-save-notice { margin-bottom: 14px; padding: 10px 12px; border: 1px solid; border-radius: 12px; font-size: 13px; font-weight: 800; text-align: center; }
.cloud-save-notice--success { border-color: #bbf7d0; background: #f0fdf4; color: #15803d; }
.cloud-save-notice--error { border-color: #fecaca; background: #fef2f2; color: #b91c1c; }
.debug-loading-message { margin: 12px auto 0; max-width: 420px; color: #64748b; font-size: 13px; line-height: 1.7; word-break: break-word; }
@keyframes slideDown { from { opacity: 0; transform: translateY(-20px); } to { opacity: 1; transform: translateY(0); } }
</style>
