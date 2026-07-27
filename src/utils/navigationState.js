export const MAIN_TAB_STORAGE_KEY = 'nikki-calculator:main-tab'
export const DEFAULT_MAIN_TAB = 'calculator'

const MAIN_TABS = new Set(['calculator', 'import', 'wardrobe', 'suits', 'contributors', 'jury', 'profile'])

export const normalizeMainTab = (tab) => (
  MAIN_TABS.has(tab) ? tab : DEFAULT_MAIN_TAB
)

export const readMainTab = (storage) => {
  try {
    const targetStorage = storage ?? globalThis.localStorage
    return normalizeMainTab(targetStorage?.getItem(MAIN_TAB_STORAGE_KEY))
  } catch {
    return DEFAULT_MAIN_TAB
  }
}

export const writeMainTab = (tab, storage) => {
  const normalizedTab = normalizeMainTab(tab)

  try {
    const targetStorage = storage ?? globalThis.localStorage
    targetStorage?.setItem(MAIN_TAB_STORAGE_KEY, normalizedTab)
  } catch {
    // 浏览器禁用本地存储时仍允许正常切换页面。
  }

  return normalizedTab
}
