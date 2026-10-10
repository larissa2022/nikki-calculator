import test from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { createMaintenanceClient, getMaintenanceConfig } from '../scripts/lib/maintenance-client.mjs'

const ref = 'tfwejruvdahonacyldrg' // 固定 development 项目；密钥和客户端均为测试替身。
const fakeKey = ['sb', 'secret', 'x'.repeat(32)].join('_')
const config = {
  SUPABASE_MAINTENANCE_URL: `https://${ref}.supabase.co`,
  SUPABASE_MAINTENANCE_PROJECT_REF: ref,
  SUPABASE_MAINTENANCE_SECRET_KEY: fakeKey
}

test('维护配置必须同时提供独立地址、标识和私密密钥，不回退到网页配置', () => {
  for (const key of Object.keys(config)) {
    const env = { ...config, [key]: '', VITE_SUPABASE_URL: config.SUPABASE_MAINTENANCE_URL,
      VITE_SUPABASE_ANON_KEY: fakeKey }
    assert.throws(() => getMaintenanceConfig(env), /未配置/)
  }
  assert.throws(() => getMaintenanceConfig({}), /未配置/)
})

test('地址必须匹配明确指定的项目，禁止凭据、路径和查询参数', () => {
  for (const url of ['not-a-url', `http://${ref}.supabase.co`,
    'https://anotherprojectrefxxx.supabase.co', `https://user:pass@${ref}.supabase.co`,
    `https://${ref}.supabase.co:1234`, `https://${ref}.supabase.co/rest/v1`,
    `https://${ref}.supabase.co?key=example`, `https://${ref}.supabase.co#example`]) {
    assert.throws(() => getMaintenanceConfig({ ...config, SUPABASE_MAINTENANCE_URL: url }))
  }
  assert.throws(() => getMaintenanceConfig({ ...config, SUPABASE_MAINTENANCE_PROJECT_REF: 'bad' }))
})

test('拒绝公开密钥及旧 JWT，错误信息不带输入内容', () => {
  for (const key of ['public-example', ['sb', 'publishable', 'x'.repeat(32)].join('_'),
    'eyJexample.invalid.signature', ['sb', 'secret', 'short'].join('_')]) {
    assert.throws(() => getMaintenanceConfig({ ...config, SUPABASE_MAINTENANCE_SECRET_KEY: key }),
      error => !error.message.includes(key) && /私密 API/.test(error.message))
  }
  const url = `https://${ref}.supabase.co?key=${fakeKey}`
  assert.throws(() => getMaintenanceConfig({ ...config, SUPABASE_MAINTENANCE_URL: url }),
    error => !error.message.includes(fakeKey) && !error.message.includes(url))
})

test('校验通过才创建客户端，禁用登录会话保存；验证不连接远端', () => {
  let calls = 0
  const sentinel = {}
  const factory = (url, key, options) => {
    calls++
    assert.equal(url, config.SUPABASE_MAINTENANCE_URL)
    assert.equal(key, fakeKey)
    assert.deepEqual(options.auth,
      { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false })
    return sentinel
  }
  assert.throws(() => createMaintenanceClient({}, factory))
  assert.equal(calls, 0)
  assert.equal(createMaintenanceClient(config, factory), sentinel)
  assert.equal(calls, 1)
})

test('两个入口缺少独立配置时，在读取数据和网络请求之前退出', () => {
  const env = { ...process.env }
  for (const key of Object.keys(config)) delete env[key]
  for (const file of ['sync_suits.js', 'upload_stages.js']) {
    const result = spawnSync(process.execPath, [file], { env, encoding: 'utf8' })
    assert.notEqual(result.status, 0)
    assert.match(result.stderr, /未配置/)
    assert.equal(result.stdout, '')
    const source = readFileSync(new URL(`../${file}`, import.meta.url), 'utf8')
    assert.match(source, /createMaintenanceClient\(\)/)
    assert.doesNotMatch(source, /https:\/\/[^\s]+\.supabase\.co|sb_secret_[A-Za-z0-9_-]{20,}/)
  }
})
