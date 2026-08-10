import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  DEFAULT_MAIN_TAB,
  MAIN_TAB_STORAGE_KEY,
  normalizeMainTabForSession,
  readMainTab,
  writeMainTab
} from '../src/utils/navigationState.js'

const donationSupportText = readFileSync(new URL('../src/components/DonationSupport.vue', import.meta.url), 'utf8')

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

  for (const tab of ['calculator', 'import', 'wardrobe', 'suits', 'contributors', 'leaderboard', 'corrections', 'jury', 'profile', 'about', 'donate']) {
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

test('退出登录或未登录重进时受限页面回退到首页', () => {
  assert.equal(normalizeMainTabForSession('jury', false, false), 'jury')
  assert.equal(normalizeMainTabForSession('jury', false), DEFAULT_MAIN_TAB)
  assert.equal(normalizeMainTabForSession('leaderboard', false), DEFAULT_MAIN_TAB)
  assert.equal(normalizeMainTabForSession('corrections', false), DEFAULT_MAIN_TAB)
  assert.equal(normalizeMainTabForSession('profile', false), DEFAULT_MAIN_TAB)
  assert.equal(normalizeMainTabForSession('jury', true), 'jury')
  assert.equal(normalizeMainTabForSession('wardrobe', false), 'wardrobe')
})

test('关于项目和打赏支持允许未登录访问', () => {
  assert.equal(normalizeMainTabForSession('about', false), 'about')
  assert.equal(normalizeMainTabForSession('donate', false), 'donate')
})

test('打赏页使用裁切二维码且不提供 GitHub 跳转', () => {
  assert.match(donationSupportText, /\/donation\/wechat-qr\.png/u)
  assert.match(donationSupportText, /\/donation\/alipay-qr\.png/u)
  assert.doesNotMatch(donationSupportText, /GitHub Issues|github\.com\/.*\/issues/iu)
  assert.doesNotMatch(donationSupportText, /付款异常如何处理|网站不接收支付回调/u)
})
