import test from 'node:test'
import assert from 'node:assert/strict'

import {
  fetchCurrentUserPoints,
  fetchMyLevelBenefits,
  fetchPointsLeaderboard,
  normalizeLeaderboardRow,
  normalizeLevelBenefits
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

test('等级权益 RPC 规范化分级数据', async () => {
  const client = {
    rpc(name) {
      assert.equal(name, 'get_my_level_benefits')
      return Promise.resolve({
        data: {
          level: 2,
          total_points: 2200,
          bonus_per_event: 2,
          vote_weight: 2,
          can_submit_review_note: true,
          admin_candidate_eligible: true,
          points_entries: [{ delta: 2 }],
          contributions: [],
          votes: [],
          community_stats: [],
          governance_stats: null,
          monthly_lv4_experience: {
            source_month: '2026-07-01',
            service_month: '2026-08-01',
            starts_at: '2026-07-31T16:00:00Z',
            scheduled_end_at: '2026-08-31T16:00:00Z',
            temporarily_applied: true
          }
        },
        error: null
      })
    }
  }

  assert.deepEqual(await fetchMyLevelBenefits(client), {
    level: 2,
    totalPoints: 2200,
    bonusPerEvent: 2,
    voteWeight: 2,
    canSubmitReviewNote: true,
    adminCandidateEligible: true,
    pointsEntries: [{ delta: 2 }],
    contributions: [],
    votes: [],
    communityStats: [],
    governanceStats: null,
    monthlyLv4Experience: {
      sourceMonth: '2026-07-01',
      serviceMonth: '2026-08-01',
      startsAt: '2026-07-31T16:00:00Z',
      scheduledEndAt: '2026-08-31T16:00:00Z',
      temporarilyApplied: true
    }
  })
  assert.equal(normalizeLevelBenefits({ level: 99 }).level, 4)
  assert.equal(normalizeLevelBenefits({}).monthlyLv4Experience, null)
  assert.equal(normalizeLevelBenefits({ monthly_lv4_experience: {} }).monthlyLv4Experience, null)
})

const createLeaderboardClient = (expectedTable, pages) => ({
  from(table) {
    assert.equal(table, expectedTable)

    const query = {
      select(columns) {
        assert.equal(columns, 'leaderboard_rank, display_name, points, current_level, is_current_user')
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
    { leaderboard_rank: 1, display_name: '甲', points: 20, current_level: 3, is_current_user: false },
    { leaderboard_rank: 2, display_name: '乙', points: 10, current_level: 2, is_current_user: true }
  ]
  const secondPage = [
    { leaderboard_rank: 3, display_name: '丙', points: 5, current_level: 1, is_current_user: false }
  ]
  const client = createLeaderboardClient('points_leaderboard_total', [
    { data: firstPage, error: null },
    { data: secondPage, error: null }
  ])

  assert.deepEqual(
    await fetchPointsLeaderboard(client, 'total', { pageSize: 2 }),
    [
      { rank: 1, displayName: '甲', points: 20, level: 3, isCurrentUser: false },
      { rank: 2, displayName: '乙', points: 10, level: 2, isCurrentUser: true },
      { rank: 3, displayName: '丙', points: 5, level: 1, isCurrentUser: false }
    ]
  )
})

test('读取当月榜并丢弃不完整的返回行', async () => {
  const client = createLeaderboardClient('points_leaderboard_current_month', [{
    data: [
      { leaderboard_rank: '1', display_name: ' 本月玩家 ', points: '8', current_level: 4, is_current_user: true },
      { leaderboard_rank: null, display_name: '', points: null, is_current_user: false }
    ],
    error: null
  }])

  assert.deepEqual(
    await fetchPointsLeaderboard(client, 'current_month'),
    [{ rank: 1, displayName: '本月玩家', points: 8, level: 4, isCurrentUser: true }]
  )
})

test('读取上月冻结榜并沿用安全公开字段', async () => {
  const client = createLeaderboardClient('points_leaderboard_last_month', [{
    data: [
      { leaderboard_rank: '1', display_name: ' 上月玩家 ', points: '12', is_current_user: false }
    ],
    error: null
  }])

  assert.deepEqual(
    await fetchPointsLeaderboard(client, 'last_month'),
    [{ rank: 1, displayName: '上月玩家', points: 12, level: 0, isCurrentUser: false }]
  )
})

test('排行榜周期和返回值校验保持默认拒绝', async () => {
  await assert.rejects(
    () => fetchPointsLeaderboard({}, 'future_month'),
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
