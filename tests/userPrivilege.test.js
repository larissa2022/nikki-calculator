import assert from 'node:assert/strict'
import test from 'node:test'

import {
  USER_LEVELS,
  getUserRankAndPrivilege
} from '../src/composables/useUserPrivilege.js'

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

test('等级徽章使用需求确认的名称与门槛', () => {
  assert.deepEqual(
    USER_LEVELS.map(({ level, threshold, badgeName }) => ({ level, threshold, badgeName })),
    [
      { level: 0, threshold: 0, badgeName: '尚未解锁等级徽章' },
      { level: 1, threshold: 500, badgeName: '铜色新星徽章' },
      { level: 2, threshold: 2000, badgeName: '银色放大镜徽章' },
      { level: 3, threshold: 5000, badgeName: '金色流光盾牌徽章' },
      { level: 4, threshold: 10000, badgeName: '至尊皇冠徽章' }
    ]
  )
})

test('升级进度按当前等级区间计算并给出下一门槛', () => {
  assert.deepEqual(
    getUserRankAndPrivilege(1250),
    {
      level: 1,
      title: '见习搭配师',
      threshold: 500,
      badgeName: '铜色新星徽章',
      badgeIcon: '✦',
      totalPoints: 1250,
      pointMultiplier: 1,
      voteWeight: 1,
      adFree: false,
      nextLevel: 2,
      nextTitle: '资深收集者',
      nextThreshold: 2000,
      pointsToNext: 750,
      progressPercent: 50,
      isMaxLevel: false
    }
  )
})

test('异常积分默认按零分展示，最高等级保持满进度', () => {
  const invalid = getUserRankAndPrivilege(Number.NaN)
  assert.equal(invalid.totalPoints, 0)
  assert.equal(invalid.level, 0)
  assert.equal(invalid.pointsToNext, 500)
  assert.equal(invalid.progressPercent, 0)

  const max = getUserRankAndPrivilege(12000)
  assert.equal(max.level, 4)
  assert.equal(max.nextThreshold, null)
  assert.equal(max.pointsToNext, 0)
  assert.equal(max.progressPercent, 100)
  assert.equal(max.isMaxLevel, true)
})
