import test from 'node:test'
import assert from 'node:assert/strict'
import {
  EMPTY_ADMIN_CAPABILITIES,
  normalizeAdminCapabilities
} from '../src/utils/adminCapabilities.js'

test('normalizeAdminCapabilities 对缺失或异常响应执行失败关闭', () => {
  assert.deepEqual(normalizeAdminCapabilities(null), EMPTY_ADMIN_CAPABILITIES)
  assert.deepEqual(normalizeAdminCapabilities([]), EMPTY_ADMIN_CAPABILITIES)
})

test('normalizeAdminCapabilities 只接受严格布尔能力并保留任期事实', () => {
  assert.deepEqual(normalizeAdminCapabilities({
    is_super_admin: false,
    can_review_low_risk: true,
    can_review_suits: 'true',
    can_permanently_reject: 1,
    can_manage_admin_terms: 'true',
    can_manage_candidate_exclusions: true,
    can_review_high_risk: 1,
    term_id: 'term-1',
    term_source: 'monthly',
    term_ends_at: '2026-08-01T00:00:00+08:00',
    show_grant_notice: true
  }), {
    is_super_admin: false,
    can_review_low_risk: true,
    can_review_suits: false,
    can_permanently_reject: false,
    can_manage_admin_terms: false,
    can_manage_candidate_exclusions: true,
    can_review_high_risk: false,
    term_id: 'term-1',
    term_source: 'monthly',
    term_ends_at: '2026-08-01T00:00:00+08:00',
    show_grant_notice: true
  })
})
