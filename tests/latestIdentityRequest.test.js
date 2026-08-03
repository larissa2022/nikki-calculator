import test from 'node:test'
import assert from 'node:assert/strict'
import { createLatestIdentityRequestGuard } from '../src/utils/latestIdentityRequest.js'

test('账号切换后旧身份请求不能再回写', () => {
  const guard = createLatestIdentityRequestGuard()
  const oldRequest = guard.begin('user-a')

  assert.equal(guard.isCurrent(oldRequest, 'user-a'), true)

  const newRequest = guard.begin('user-b')

  assert.equal(guard.isCurrent(oldRequest, 'user-a'), false)
  assert.equal(guard.isCurrent(oldRequest, 'user-b'), false)
  assert.equal(guard.isCurrent(newRequest, 'user-b'), true)
})

test('退出登录会使仍在执行的身份请求失效', () => {
  const guard = createLatestIdentityRequestGuard()
  const request = guard.begin('user-a')

  guard.invalidate()

  assert.equal(guard.isCurrent(request, 'user-a'), false)
  assert.equal(guard.isCurrent(request, null), false)
})
