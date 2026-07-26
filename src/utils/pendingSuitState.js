const normalizeText = (value) => String(value ?? '').trim()

export const restorePendingSuitState = (pendingItem = {}) => {
  const suitId = normalizeText(pendingItem.suit_id)
  const tempSuitName = normalizeText(pendingItem.temp_suit_name)

  if (suitId) {
    return {
      suitId,
      status: 'existing',
      searchText: ''
    }
  }

  if (tempSuitName) {
    return {
      suitId: '',
      status: 'new',
      searchText: tempSuitName
    }
  }

  if (pendingItem.needs_suit_review === true) {
    return {
      suitId: '',
      status: 'pending_review',
      searchText: ''
    }
  }

  return {
    suitId: '',
    status: 'none',
    searchText: ''
  }
}
