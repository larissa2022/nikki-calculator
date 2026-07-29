import assert from 'node:assert/strict'
import test from 'node:test'

import { getUserRankAndPrivilege } from '../src/composables/useUserPrivilege.js'

test('积分等级使用已确认的四级门槛', () => {
  assert.deepEqual(
    [0, 500, 2000, 5000, 10000].map(points => getUserRankAndPrivilege(points).level),
    [0, 1, 2, 3, 4]
  )
  assert.equal(getUserRankAndPrivilege(499).level, 0)
})

test('所有等级都按一人一票且不改变积分倍率', () => {
  for (const points of [0, 500, 2000, 5000, 10000]) {
    const privilege = getUserRankAndPrivilege(points)
    assert.equal(privilege.voteWeight, 1)
    assert.equal(privilege.pointMultiplier, 1)
  }
})

test('等级本身不直接授予广告免除权', () => {
  assert.equal(getUserRankAndPrivilege(10000).adFree, false)
  assert.equal(getUserRankAndPrivilege(0).adFree, false)
})

test('当月榜首不在第一版自动获得 Lv4', () => {
  assert.equal(getUserRankAndPrivilege(0).level, 0)
})
