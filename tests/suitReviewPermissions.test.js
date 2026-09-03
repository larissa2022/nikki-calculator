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
  assert.match(lowRiskAdminView, />图鉴管理</)
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
  assert.match(governanceBoard, /手动任期只由站长管理/)
  assert.match(correctionBoard, /重新审核/)
  assert.match(correctionBoard, /请换一位管理员/)
})

test('普通管理员页面不显示手动任期入口', async () => {
  const [lowRiskAdminView, adminView, juryBoard] = await Promise.all([
    readSource('../src/views/LowRiskAdminView.vue'),
    readSource('../src/views/AdminView.vue'),
    readSource('../src/components/JuryReviewBoard.vue')
  ])

  assert.match(lowRiskAdminView, /can_manage_candidate_exclusions/)
  assert.doesNotMatch(lowRiskAdminView, /can_manage_admin_terms/)
  assert.match(lowRiskAdminView, /:allow-term-management="false"/)
  assert.match(adminView, /:allow-term-management="true"/)
  assert.match(await readSource('../src/composables/useAuth.js'), /can_manage_admin_terms: data\?\.role === 'super_admin',/)
  assert.match(juryBoard, /你已经投过这一项，不能再终审/)
})

test('普通提交入口不再发送受保护的 pending 状态字段', async () => {
  const [suitService, contributionService] = await Promise.all([
    readSource('../src/api/suitService.js'),
    readSource('../src/api/contributionService.js')
  ])

  assert.doesNotMatch(suitService, /status:\s*'pending'/)
  assert.doesNotMatch(contributionService, /status:\s*'pending'/)
})
