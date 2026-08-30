import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const readSource = path => readFile(new URL(path, import.meta.url), 'utf8')

test('套装审核前端只调用 DB-21 受控 RPC', async () => {
  const [adminService, adminCapabilitiesService, adminView, lowRiskAdminView] = await Promise.all([
    readSource('../src/api/adminService.js'),
    readSource('../src/api/adminCapabilitiesService.js'),
    readSource('../src/views/AdminView.vue'),
    readSource('../src/views/LowRiskAdminView.vue')
  ])

  assert.match(adminService, /rpc\('list_pending_suits_for_review'\)/)
  assert.match(adminService, /rpc\('review_pending_suit'/)
  assert.match(adminService, /p_reason:/)
  assert.match(adminService, /allowWithoutPending \? 'create' : 'approve'/)
  assert.match(adminCapabilitiesService, /rpc\('list_pending_suits_for_review'\)/)
  assert.match(adminCapabilitiesService, /rpc\('review_pending_suit'/)
  assert.match(lowRiskAdminView, /社区图鉴管理/)
  assert.match(lowRiskAdminView, /CommunitySuitReviewBoard/)
  assert.doesNotMatch(adminService, /from\('suits'\)\s*\r?\n\s*\.upsert/)
  assert.doesNotMatch(adminService, /from\('pending_suits'\)\s*\r?\n\s*\.delete/)
  assert.doesNotMatch(adminService, /from\('pending_suits'\)\s*\r?\n\s*\.update/)
  assert.doesNotMatch(adminView, /from\('suits'\)/)
})

test('社区共治前端使用受控治理与纠错 RPC', async () => {
  const [service, governanceBoard, correctionBoard] = await Promise.all([
    readSource('../src/api/adminCapabilitiesService.js'),
    readSource('../src/components/AdminGovernanceBoard.vue'),
    readSource('../src/components/CommunityCorrectionBoard.vue')
  ])

  assert.match(service, /rpc\('submit_admin_governance_action'/)
  assert.match(service, /rpc\('list_rejected_jury_items_for_reopen'\)/)
  assert.match(service, /rpc\('reopen_rejected_jury_candidate'/)
  assert.match(governanceBoard, /3 位不同的当前有效普通管理员共签/)
  assert.match(correctionBoard, /纠错/)
})

test('普通提交入口不再发送受保护的 pending 状态字段', async () => {
  const [suitService, contributionService] = await Promise.all([
    readSource('../src/api/suitService.js'),
    readSource('../src/api/contributionService.js')
  ])

  assert.doesNotMatch(suitService, /status:\s*'pending'/)
  assert.doesNotMatch(contributionService, /status:\s*'pending'/)
})
