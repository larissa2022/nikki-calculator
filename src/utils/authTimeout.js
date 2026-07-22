const DEFAULT_TIMEOUT_MESSAGE = '网络请求超时，请检查网络后重试。'
const RESET_TIMEOUT_MESSAGE = '重置请求响应超时，密码可能已经更新。为避免重复提交，请先使用新密码登录；如果无法登录，再重新找回密码。'

export const getAuthTimeoutRecovery = (submittedMode) => (
  submittedMode === 'reset'
    ? {
        nextMode: 'login',
        clearSensitiveFields: true,
        message: RESET_TIMEOUT_MESSAGE,
        type: 'warning'
      }
    : {
        nextMode: submittedMode,
        clearSensitiveFields: false,
        message: DEFAULT_TIMEOUT_MESSAGE,
        type: 'error'
      }
)
