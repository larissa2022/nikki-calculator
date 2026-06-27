import { createClient } from '@supabase/supabase-js'

// 你的 Supabase 配置 (请保留你原本的 URL 和 Anon Key)
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseKey) {
  throw new Error('Missing Supabase environment variables: VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY')
}

// 1. 确保开启了自动刷新和持久化会话
export const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
  }
})

// 🌟 2. 核心补丁：监听网页的“唤醒”事件
if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => {
    // 当用户从其他标签页切回当前网页时
    if (document.visibilityState === 'visible') {
      console.log('🔄 网页已唤醒，正在恢复 Supabase 连接...')
      // 强制触发一次 Session 获取，这会让 Supabase 内部重新激活定时器并刷新过期 Token
      supabase.auth.getSession().then(({ error }) => {
        if (error) console.error('唤醒会话失败:', error.message)
      })
    }
  })
}
// src/api/supabase.js (在文件末尾添加)

export const logErrorToCloud = async (actionName, err, userId = null) => {
  try {
    await supabase.from('app_errors').insert([{
      action_name: actionName,
      error_message: err.message || String(err),
      error_stack: err.stack || 'No stack trace',
      user_id: userId,
      // 🌟 这句话极其关键！能帮你查出是不是特定型号的手机或者特定版本的微信出了问题
      user_agent: navigator.userAgent 
    }]);
  } catch (e) {
    // 如果上报错误本身也失败了，就默默吞掉，不要影响用户体验
    console.warn('日志上报失败', e);
  }
}
