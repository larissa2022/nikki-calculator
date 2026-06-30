export const ROLE_KEY = {
  USER: 'user',
  ADMIN: 'admin',
  SUPER_ADMIN: 'super_admin'
}

export const ROLE_LEVEL = {
  USER: 0,
  ADMIN: 1,
  SUPER_ADMIN: 2
}

const keyToLevel = {
  [ROLE_KEY.USER]: ROLE_LEVEL.USER,
  [ROLE_KEY.ADMIN]: ROLE_LEVEL.ADMIN,
  [ROLE_KEY.SUPER_ADMIN]: ROLE_LEVEL.SUPER_ADMIN
}

const levelToKey = {
  [ROLE_LEVEL.USER]: ROLE_KEY.USER,
  [ROLE_LEVEL.ADMIN]: ROLE_KEY.ADMIN,
  [ROLE_LEVEL.SUPER_ADMIN]: ROLE_KEY.SUPER_ADMIN
}

const levelToLabel = {
  [ROLE_LEVEL.USER]: '玩家',
  [ROLE_LEVEL.ADMIN]: '系统管理',
  [ROLE_LEVEL.SUPER_ADMIN]: '最高站长'
}

export const getRoleLevel = (value) => {
  if (value && typeof value === 'object') {
    if (value.role_level !== null && value.role_level !== undefined) {
      return Number(value.role_level)
    }
    return keyToLevel[value.role] ?? ROLE_LEVEL.USER
  }

  if (typeof value === 'number') return value
  if (typeof value === 'string' && value.trim() !== '') {
    const numeric = Number(value)
    if (Number.isInteger(numeric)) return numeric
    return keyToLevel[value] ?? ROLE_LEVEL.USER
  }

  return ROLE_LEVEL.USER
}

export const getRoleKey = (value) => levelToKey[getRoleLevel(value)] ?? ROLE_KEY.USER

export const getRoleLabel = (value) => levelToLabel[getRoleLevel(value)] ?? levelToLabel[ROLE_LEVEL.USER]

export const isAdminRole = (value) => getRoleLevel(value) >= ROLE_LEVEL.ADMIN

export const isSuperAdminRole = (value) => getRoleLevel(value) === ROLE_LEVEL.SUPER_ADMIN

export const getRoleUpdatePayload = (value) => {
  const roleLevel = getRoleLevel(value)
  return {
    role_level: roleLevel,
    role: getRoleKey(roleLevel)
  }
}
