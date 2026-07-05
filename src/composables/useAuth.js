import { ref, computed } from 'vue'
import { supabase } from '../api/supabase'
import { isAdminRole } from '../utils/roles'

// 🌟 1. 【核心修复】将状态提升到函数外部！
// 这样全站无论调用多少次 useAuth()，读写的都是这一份真实的数据（单例模式）
const currentUser = ref(null)
const userProfile = ref(null)
let authSubscription = null

// 🌟 让 isAdmin 逻辑同时兼容“普通管理”和“超级管理”
const isAdmin = computed(() => {
  return isAdminRole(userProfile.value)
})

export function useAuth() {
  
  // 🌟 主动拉取/刷新用户档案（积分、昵称、权限）
  const fetchProfile = async () => {
    if (!currentUser.value) return
    
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', currentUser.value.id)
        .single() // 必须加上 eq 限定，否则查全表会报错
        
      if (error) throw error
      userProfile.value = data // 更新全局档案
    } catch (err) {
      console.error('获取全局用户档案失败:', err.message)
    }
  }

  // 清空本地状态
  const resetState = (clearAuth = true) => {
    if (clearAuth) currentUser.value = null
    userProfile.value = null
  }

  // 🌟 初始化鉴权系统与监听
  const initAuth = async () => {
    // 1. 全局监听只注册一次，避免 initAuth 重复调用时叠加回调
    if (!authSubscription) {
      const { data } = supabase.auth.onAuthStateChange(async (event, session) => {
        if (event === 'SIGNED_OUT') {
          resetState(true)
        } else {
          currentUser.value = session?.user || null
          if (currentUser.value) await fetchProfile()
          else resetState(false)
        }
      })
      authSubscription = data?.subscription || true
    }

    // 2. 每次初始化仍刷新当前 Session，确保页面唤醒或重挂载后状态准确
    const { data: { session } } = await supabase.auth.getSession()
    currentUser.value = session?.user || null
    if (currentUser.value) await fetchProfile()
    else resetState(false)
  }

  // 🌟 移除了 userQuota，并暴露必要的全局状态和方法
  return { currentUser, userProfile, isAdmin, fetchProfile, initAuth }
}
