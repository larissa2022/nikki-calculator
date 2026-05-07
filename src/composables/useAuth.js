import { ref, computed } from 'vue'
import { supabase } from '../api/supabase'

export function useAuth() {
  const currentUser = ref(null)
  const userProfile = ref(null)

  // 🌟 修改 1：让 isAdmin 逻辑同时兼容“普通管理”和“超级管理”
  const isAdmin = computed(() => {
    const role = userProfile.value?.role
    return role === 'admin' || role === 'super_admin'
  })
  
  const userQuota = computed(() => userProfile.value?.quota || 0)

  const fetchProfile = async () => {
    if (!currentUser.value) return
    // 🌟 修改 2：必须加上 .eq('id', ...) 否则一旦有多个用户，.single() 会直接报错
    const { data } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', currentUser.value.id)
      .single()
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