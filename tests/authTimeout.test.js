import assert from 'node:assert/strict'
import test from 'node:test'

import { getAuthTimeoutRecovery } from '../src/utils/authTimeout.js'

test('重置密码响应超时后返回登录并提示结果不确定', () => {
  const recovery = getAuthTimeoutRecovery('reset')

  assert.equal(recovery.nextMode, 'login')
  assert.equal(recovery.clearSensitiveFields, true)
  assert.match(recovery.message, /可能已经更新/)
  assert.match(recovery.message, /先使用新密码登录/)
})

test('其他认证请求超时保持当前流程且不清空输入', () => {
  const recovery = getAuthTimeoutRecovery('register')

  assert.equal(recovery.nextMode, 'register')
  assert.equal(recovery.clearSensitiveFields, false)
})
