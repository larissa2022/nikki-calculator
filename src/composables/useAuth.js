import { ref, computed } from 'vue'
import { supabase } from '../api/supabase'

export function useAuth() {
  const currentUser = ref(null)
  const userProfile = ref(null)

  // 🌟 核心修改处：同时识别普通管理员和超级管理员！
  const isAdmin = computed(() => userProfile.value?.role === 'admin' || userProfile.value?.role === 'super_admin')
  
  const userQuota = computed(() => userProfile.value?.quota || 0)

  const fetchProfile = async () => {
    if (!currentUser.value) return
    const { data } = await supabase.from('profiles').select('*').single()
    if (data) userProfile.value = data
  }

  const initAuth = async () => {
    const { data: { session } } = await supabase.auth.getSession()
    currentUser.value = session?.user || null
    if (currentUser.value) await fetchProfile()

    supabase.auth.onAuthStateChange(async (event, session) => {
      currentUser.value = session?.user || null
      if (currentUser.value) await fetchProfile()
      else userProfile.value = null
    })
  }

  return { currentUser, userProfile, isAdmin, userQuota, fetchProfile, initAuth }
}