export const createLatestIdentityRequestGuard = () => {
  let sequence = 0

  return {
    begin(userId) {
      sequence += 1
      return { sequence, userId: userId || null }
    },

    invalidate() {
      sequence += 1
    },

    isCurrent(request, currentUserId) {
      return Boolean(
        request?.userId
        && request.sequence === sequence
        && request.userId === (currentUserId || null)
      )
    }
  }
}
