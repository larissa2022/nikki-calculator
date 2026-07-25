import assert from 'node:assert/strict'
import test from 'node:test'

import {
  buildContributorEntries,
  fetchPublicClothingContributors
} from '../src/api/contributorsService.js'

const createClient = (pages) => ({
  from(table) {
    assert.equal(table, 'clothing_contributors_public')

    const query = {
      select(columns) {
        assert.equal(columns, 'clothes_id, contribution_rank, display_name, contributed_at')
        return query
      },
      order(column, options) {
        assert.ok(['clothes_id', 'contribution_rank'].includes(column))
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

test('分页读取公开的前 3 贡献者视图', async () => {
  const firstPage = [
    { clothes_id: 'c1', contribution_rank: 1, display_name: '甲', contributed_at: '2026-07-01T00:00:00Z' },
    { clothes_id: 'c1', contribution_rank: 2, display_name: '乙', contributed_at: '2026-07-02T00:00:00Z' }
  ]
  const secondPage = [
    { clothes_id: 'c2', contribution_rank: 1, display_name: '丙', contributed_at: '2026-07-03T00:00:00Z' }
  ]
  const client = createClient([
    { data: firstPage, error: null },
    { data: secondPage, error: null }
  ])

  assert.deepEqual(
    await fetchPublicClothingContributors(client, { pageSize: 2 }),
    [...firstPage, ...secondPage]
  )
})

test('贡献者视图读取失败时保留原始错误', async () => {
  const queryError = { code: '42501', message: 'permission denied' }
  const client = createClient([{ data: null, error: queryError }])

  await assert.rejects(
    () => fetchPublicClothingContributors(client),
    error => error === queryError
  )
})

test('按服装聚合并稳定展示前 3 位贡献者', () => {
  const rows = [
    { clothes_id: 'c1', contribution_rank: 3, display_name: '第三位', contributed_at: '2026-07-03T00:00:00Z' },
    { clothes_id: 'c1', contribution_rank: 1, display_name: '第一位', contributed_at: '2026-07-01T00:00:00Z' },
    { clothes_id: 'c1', contribution_rank: 2, display_name: '第二位', contributed_at: '2026-07-02T00:00:00Z' },
    { clothes_id: 'c1', contribution_rank: 2, display_name: '重复第二位', contributed_at: '2026-07-04T00:00:00Z' },
    { clothes_id: 'c2', contribution_rank: 1, display_name: '已注销用户', contributed_at: '2026-07-05T00:00:00Z' },
    { clothes_id: '', contribution_rank: 1, display_name: '无效行', contributed_at: null }
  ]
  const clothes = [
    { id: 'c1', name: '星光长裙', game_id: '1001', category: '连衣裙' }
  ]

  const entries = buildContributorEntries(rows, clothes)

  assert.equal(entries.length, 2)
  assert.equal(entries[0].clothesId, 'c2')
  assert.equal(entries[0].name, '未知服装（c2）')
  assert.deepEqual(
    entries[1].contributors.map(item => [item.rank, item.displayName]),
    [[1, '第一位'], [2, '第二位'], [3, '第三位']]
  )
  assert.equal(entries[1].name, '星光长裙')
})
