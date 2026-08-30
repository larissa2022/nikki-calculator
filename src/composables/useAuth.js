import { ref, computed } from 'vue'
import { supabase } from '../api/supabase'
import {
  fetchAdminCapabilities
} from '../api/adminCapabilitiesService'
import {
  EMPTY_ADMIN_CAPABILITIES,
  normalizeAdminCapabilities
} from '../utils/adminCapabilities'
import { createLatestIdentityRequestGuard } from '../utils/latestIdentityRequest'

// 🌟 1. 【核心修复】将状态提升到函数外部！
// 这样全站无论调用多少次 useAuth()，读写的都是这一份真实的数据（单例模式）
const currentUser = ref(null)
const userProfile = ref(null)
const adminCapabilities = ref(normalizeAdminCapabilities())
const isAuthInitialized = ref(false)
let authListenerRegistered = false
const profileRequestGuard = createLatestIdentityRequestGuard()

// 🌟 让 isAdmin 逻辑同时兼容“普通管理”和“超级管理”
const isAdmin = computed(() => {
  return adminCapabilities.value.can_review_low_risk === true
})

export function useAuth() {
  
  // 🌟 主动拉取/刷新用户档案（积分、昵称、权限）
  const fetchProfile = async () => {
    const userId = currentUser.value?.id
    if (!userId) return

    const request = profileRequestGuard.begin(userId)
    const isCurrentRequest = () => profileRequestGuard.isCurrent(request, currentUser.value?.id)

    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single()

      if (error) throw error
      if (!isCurrentRequest()) return
      userProfile.value = data

      try {
        const nextCapabilities = await fetchAdminCapabilities()
        if (!isCurrentRequest()) return
        adminCapabilities.value = nextCapabilities
      } catch (capabilityError) {
        if (!isCurrentRequest()) return
        console.error('获取管理员能力失败:', capabilityError.message)
        adminCapabilities.value = normalizeAdminCapabilities({
          is_super_admin: data?.role === 'super_admin' || Number(data?.role_level) === 2,
          can_review_low_risk: data?.role === 'super_admin' || Number(data?.role_level) === 2,
          can_review_suits: data?.role === 'super_admin' || Number(data?.role_level) === 2,
          can_permanently_reject: data?.role === 'super_admin' || Number(data?.role_level) === 2,
          can_manage_admin_terms: data?.role === 'super_admin' || Number(data?.role_level) === 2,
          can_review_high_risk: data?.role === 'super_admin' || Number(data?.role_level) === 2
        })
      }
    } catch (err) {
      if (!isCurrentRequest()) return
      console.error('获取全局用户档案失败:', err.message)
    }
  }

  // 清空本地状态
  const resetState = (clearAuth = true) => {
    profileRequestGuard.invalidate()
    if (clearAuth) currentUser.value = null
    userProfile.value = null
    adminCapabilities.value = { ...EMPTY_ADMIN_CAPABILITIES }
  }

  const startSession = (user, scheduleFetch = true) => {
    const nextUser = user || null
    const userChanged = currentUser.value?.id !== nextUser?.id

    if (userChanged) {
      profileRequestGuard.invalidate()
      userProfile.value = null
      adminCapabilities.value = { ...EMPTY_ADMIN_CAPABILITIES }
    }

    currentUser.value = nextUser
    if (nextUser) {
      if (scheduleFetch) setTimeout(() => { void fetchProfile() }, 0)
    } else {
      resetState(false)
    }
  }

  // 🌟 初始化鉴权系统与监听
  const initAuth = async () => {
    // 1. 全局监听只注册一次，避免页面重新挂载后重复处理同一鉴权事件。
    if (!authListenerRegistered) {
      supabase.auth.onAuthStateChange((event, session) => {
        if (event === 'SIGNED_OUT') {
          resetState(true)
        } else {
          startSession(session?.user || null)
        }
        isAuthInitialized.value = true
      })
      authListenerRegistered = true
    }

    // 2. 初次加载时获取 Session；无论成功或失败，都结束“鉴权未知”状态。
    try {
      const { data: { session } } = await supabase.auth.getSession()
      startSession(session?.user || null, false)
      if (currentUser.value) await fetchProfile()
    } finally {
      isAuthInitialized.value = true
    }
  }

  // 🌟 移除了 userQuota，并暴露必要的全局状态和方法
  return { currentUser, userProfile, adminCapabilities, isAdmin, isAuthInitialized, fetchProfile, initAuth }
}
