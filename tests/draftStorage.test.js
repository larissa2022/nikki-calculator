import test from 'node:test'
import assert from 'node:assert/strict'
import { createScopedDraftKey, readFreshDraft, removeDraft, writeDraft } from '../src/utils/draftStorage.js'

const createMemoryStorage = () => {
  const values = new Map()
  return {
    getItem: (key) => values.has(key) ? values.get(key) : null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
    has: (key) => values.has(key)
  }
}

test('草稿键按用户和表单项隔离', () => {
  const firstUser = createScopedDraftKey('nikki.missingItemDraft.v2:', 'user-a', '连衣裙')
  const secondUser = createScopedDraftKey('nikki.missingItemDraft.v2:', 'user-b', '连衣裙')
  const secondItem = createScopedDraftKey('nikki.missingItemDraft.v2:', 'user-a', '外套')

  assert.notEqual(firstUser, secondUser)
  assert.notEqual(firstUser, secondItem)
  assert.match(firstUser, /^nikki\.missingItemDraft\.v2:user-a:/)
})

test('有效期内草稿可恢复且保留更新时间', () => {
  const storage = createMemoryStorage()
  const key = createScopedDraftKey('nikki.importZoneDraft.v2:', 'user-a')
  const now = 1_000_000

  assert.equal(writeDraft(storage, key, { importText: '星光礼赞' }, now), true)
  assert.deepEqual(readFreshDraft(storage, key, 24 * 60 * 60 * 1000, now + 1000), {
    importText: '星光礼赞',
    updatedAt: now
  })
})

test('超过 24 小时的草稿会被清理', () => {
  const storage = createMemoryStorage()
  const key = createScopedDraftKey('nikki.importZoneDraft.v2:', 'user-a')
  const ttlMs = 24 * 60 * 60 * 1000

  writeDraft(storage, key, { importText: '旧草稿' }, 1000)
  assert.equal(readFreshDraft(storage, key, ttlMs, 1000 + ttlMs + 1), null)
  assert.equal(storage.has(key), false)
})

test('提交成功后可移除对应草稿且不影响其他用户', () => {
  const storage = createMemoryStorage()
  const firstKey = createScopedDraftKey('nikki.missingItemDraft.v2:', 'user-a', '连衣裙')
  const secondKey = createScopedDraftKey('nikki.missingItemDraft.v2:', 'user-b', '连衣裙')

  writeDraft(storage, firstKey, { form: { name: '星光礼赞' } }, 1000)
  writeDraft(storage, secondKey, { form: { name: '星光礼赞' } }, 1000)
  assert.equal(removeDraft(storage, firstKey), true)
  assert.equal(storage.has(firstKey), false)
  assert.equal(storage.has(secondKey), true)
})
