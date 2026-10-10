import { createClient } from '@supabase/supabase-js'

// Only trusted Node maintenance scripts import this module; never use VITE_*.
export function getMaintenanceConfig(env = process.env) {
  const url = env.SUPABASE_MAINTENANCE_URL
  const projectRef = env.SUPABASE_MAINTENANCE_PROJECT_REF
  const secretKey = env.SUPABASE_MAINTENANCE_SECRET_KEY
  if (!url || !projectRef || !secretKey) {
    throw new Error('维护脚本未配置：需要独立的项目地址、项目标识和私密密钥；未连接数据库。')
  }

  let parsed
  try { parsed = new URL(url) } catch {
    throw new Error('维护项目地址无效；未连接数据库。')
  }
  if (!/^[a-z]{20}$/.test(projectRef) ||
      parsed.protocol !== 'https:' ||
      parsed.hostname !== `${projectRef}.supabase.co` ||
      parsed.port || parsed.username || parsed.password ||
      parsed.pathname !== '/' || parsed.search || parsed.hash) {
    throw new Error('维护项目地址与项目标识不一致，或地址包含多余内容；未连接数据库。')
  }
  if (!/^sb_secret_[A-Za-z0-9_-]{20,}$/.test(secretKey)) {
    throw new Error('维护脚本只接受独立的私密 API 密钥，不接受网页公开密钥或旧版 JWT 密钥；未连接数据库。')
  }
  return { url: parsed.origin, secretKey }
}

export function createMaintenanceClient(env = process.env, factory = createClient) {
  const { url, secretKey } = getMaintenanceConfig(env)
  return factory(url, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
  })
}
