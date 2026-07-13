export const createScopedDraftKey = (prefix, ownerId, ...parts) => {
  const cleanPrefix = String(prefix || '').replace(/:+$/, '')
  return [cleanPrefix, ownerId || 'guest', ...parts]
    .map((part, index) => index === 0 ? part : encodeURIComponent(String(part || '')))
    .join(':')
}

export const readFreshDraft = (storage, key, ttlMs, now = Date.now()) => {
  try {
    const raw = storage.getItem(key)
    if (!raw) return null
    const draft = JSON.parse(raw)
    if (!draft?.updatedAt || now - draft.updatedAt > ttlMs) {
      storage.removeItem(key)
      return null
    }
    return draft
  } catch {
    try { storage.removeItem(key) } catch {}
    return null
  }
}

export const writeDraft = (storage, key, payload, now = Date.now()) => {
  try {
    storage.setItem(key, JSON.stringify({ ...payload, updatedAt: now }))
    return true
  } catch {
    return false
  }
}

export const removeDraft = (storage, key) => {
  try {
    storage.removeItem(key)
    return true
  } catch {
    return false
  }
}
