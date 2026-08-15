import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const readSource = path => readFile(new URL(path, import.meta.url), 'utf8')

test('套装审核前端只调用 DB-21 受控 RPC', async () => {
  const [adminService, adminView] = await Promise.all([
    readSource('../src/api/adminService.js'),
    readSource('../src/views/AdminView.vue')
  ])

  assert.match(adminService, /rpc\('list_pending_suits_for_review'\)/)
  assert.match(adminService, /rpc\('review_pending_suit'/)
  assert.match(adminService, /allowWithoutPending \? 'create' : 'approve'/)
  assert.doesNotMatch(adminService, /from\('suits'\)\s*\r?\n\s*\.upsert/)
  assert.doesNotMatch(adminService, /from\('pending_suits'\)\s*\r?\n\s*\.delete/)
  assert.doesNotMatch(adminService, /from\('pending_suits'\)\s*\r?\n\s*\.update/)
  assert.doesNotMatch(adminView, /from\('suits'\)/)
})

test('普通提交入口不再发送受保护的 pending 状态字段', async () => {
  const [suitService, contributionService] = await Promise.all([
    readSource('../src/api/suitService.js'),
    readSource('../src/api/contributionService.js')
  ])

  assert.doesNotMatch(suitService, /status:\s*'pending'/)
  assert.doesNotMatch(contributionService, /status:\s*'pending'/)
})
