import test from 'node:test'
import assert from 'node:assert/strict'

import { fetchCurrentUserPoints } from '../src/api/pointsService.js'

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
