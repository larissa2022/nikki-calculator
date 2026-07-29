import test from 'node:test'
import assert from 'node:assert/strict'

import {
  fetchCurrentUserPoints,
  fetchPointsLeaderboard,
  normalizeLeaderboardRow
} from '../src/api/pointsService.js'

const createClient = (response) => ({
  from(table) {
    assert.equal(table, 'user_points_summary')
    return {
      select(columns) {
        assert.equal(columns, 'total_points')
        return {
          limit(count) {
            assert.equal(count, 1)
            return Promise.resolve(response)
          }
        }
      }
    }
  }
})

test('读取当前用户的权威累计积分', async () => {
  const client = createClient({ data: [{ total_points: 18 }], error: null })

  assert.equal(await fetchCurrentUserPoints(client), 18)
})

test('无积分流水时返回 0', async () => {
  const client = createClient({ data: [{ total_points: null }], error: null })

  assert.equal(await fetchCurrentUserPoints(client), 0)
})

test('查询失败时保留错误供界面处理', async () => {
  const queryError = { code: '42501', message: 'permission denied' }
  const client = createClient({ data: null, error: queryError })

  await assert.rejects(
    () => fetchCurrentUserPoints(client),
    (error) => error === queryError
  )
})

const createLeaderboardClient = (expectedTable, pages) => ({
  from(table) {
    assert.equal(table, expectedTable)

    const query = {
      select(columns) {
        assert.equal(columns, 'leaderboard_rank, display_name, points, is_current_user')
        return query
      },
      order(column, options) {
        assert.ok(['leaderboard_rank', 'display_name'].includes(column))
        assert.deepEqual(options, { ascending: true })
        return query
      },
      range(from, to) {
        const pageSize = to - from + 1
        const pageIndex = Math.floor(from / pageSize)
        return Promise.resolve(pages[pageIndex])
      }
    }

    return query
  }
})

test('分页读取总榜并规范化数据库字段', async () => {
  const firstPage = [
    { leaderboard_rank: 1, display_name: '甲', points: 20, is_current_user: false },
    { leaderboard_rank: 2, display_name: '乙', points: 10, is_current_user: true }
  ]
  const secondPage = [
    { leaderboard_rank: 3, display_name: '丙', points: 5, is_current_user: false }
  ]
  const client = createLeaderboardClient('points_leaderboard_total', [
    { data: firstPage, error: null },
    { data: secondPage, error: null }
  ])

  assert.deepEqual(
    await fetchPointsLeaderboard(client, 'total', { pageSize: 2 }),
    [
      { rank: 1, displayName: '甲', points: 20, isCurrentUser: false },
      { rank: 2, displayName: '乙', points: 10, isCurrentUser: true },
      { rank: 3, displayName: '丙', points: 5, isCurrentUser: false }
    ]
  )
})

test('读取当月榜并丢弃不完整的返回行', async () => {
  const client = createLeaderboardClient('points_leaderboard_current_month', [{
    data: [
      { leaderboard_rank: '1', display_name: ' 本月玩家 ', points: '8', is_current_user: true },
      { leaderboard_rank: null, display_name: '', points: null, is_current_user: false }
    ],
    error: null
  }])

  assert.deepEqual(
    await fetchPointsLeaderboard(client, 'current_month'),
    [{ rank: 1, displayName: '本月玩家', points: 8, isCurrentUser: true }]
  )
})

test('排行榜周期和返回值校验保持默认拒绝', async () => {
  await assert.rejects(
    () => fetchPointsLeaderboard({}, 'last_month'),
    /不支持的排行榜周期/
  )
  assert.equal(normalizeLeaderboardRow({ leaderboard_rank: 0, display_name: '甲', points: 1 }), null)
  assert.equal(normalizeLeaderboardRow({ leaderboard_rank: 1, display_name: '', points: 1 }), null)
})

test('排行榜查询失败时保留数据库错误', async () => {
  const queryError = { code: '42501', message: 'permission denied' }
  const client = createLeaderboardClient('points_leaderboard_total', [{ data: null, error: queryError }])

  await assert.rejects(
    () => fetchPointsLeaderboard(client, 'total'),
    error => error === queryError
  )
})
