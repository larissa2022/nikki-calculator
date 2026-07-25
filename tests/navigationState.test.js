import assert from 'node:assert/strict'
import test from 'node:test'

import {
  DEFAULT_MAIN_TAB,
  MAIN_TAB_STORAGE_KEY,
  readMainTab,
  writeMainTab
} from '../src/utils/navigationState.js'

const createStorage = (initialValue = null) => {
  let value = initialValue
  return {
    getItem: (key) => key === MAIN_TAB_STORAGE_KEY ? value : null,
    setItem: (key, nextValue) => {
      if (key === MAIN_TAB_STORAGE_KEY) value = nextValue
    }
  }
}

test('刷新后恢复每个合法的主页面位置', () => {
  const storage = createStorage()

  for (const tab of ['calculator', 'import', 'wardrobe', 'suits', 'contributors', 'profile']) {
    assert.equal(writeMainTab(tab, storage), tab)
    assert.equal(readMainTab(storage), tab)
  }
})

test('非法或过期的页面缓存回退到首页', () => {
  assert.equal(readMainTab(createStorage('unknown-tab')), DEFAULT_MAIN_TAB)
})

test('本地存储不可用时页面切换仍然可用', () => {
  const blockedStorage = {
    getItem: () => { throw new Error('blocked') },
    setItem: () => { throw new Error('blocked') }
  }

  assert.equal(readMainTab(blockedStorage), DEFAULT_MAIN_TAB)
  assert.equal(writeMainTab('suits', blockedStorage), 'suits')
})
