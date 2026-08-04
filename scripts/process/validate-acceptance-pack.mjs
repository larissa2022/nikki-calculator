import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REQUIRED_TEXT = [
  '验收批次',
  '目标 PR',
  '目标提交',
  '测试入口',
  '## 验收范围',
  '## 已准备数据',
  '## 最短验收流程',
  '预期结果',
  '总通过标准',
  '## 异常反馈',
  '## 数据保留与清理',
  '## Rollback'
]

const SIMPLE_PASSWORD = /^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,16}$/u
const INVALID_ACCOUNT = /^(?:<.*>|待填写|沿用|见.*|无|已清除.*)$/u

const getSection = (source, heading) => {
  const headingMatch = new RegExp(`^## ${heading}\\s*$`, 'mu').exec(source)
  if (!headingMatch) return ''

  const sectionStart = headingMatch.index + headingMatch[0].length
  const remaining = source.slice(sectionStart)
  const nextSection = /^##\s+/mu.exec(remaining)
  return nextSection ? remaining.slice(0, nextSection.index) : remaining
}

const getTestModules = source => {
  const flow = getSection(source, '最短验收流程')
  const headings = [...flow.matchAll(/^###\s+(.+)\s*$/gmu)]

  return headings.map((match, index) => {
    const bodyStart = match.index + match[0].length
    const bodyEnd = headings[index + 1]?.index ?? flow.length
    return {
      heading: match[1].trim(),
      body: flow.slice(bodyStart, bodyEnd)
    }
  })
}

const getCredentialValues = (source, label) => [
  ...source.matchAll(new RegExp(`^${label}\\s*[:：]\\s*(\\S+)\\s*$`, 'gmu'))
].map(match => match[1])

export const validateAcceptancePackText = text => {
  const errors = []
  const source = String(text || '')

  if (!/^# .+验收清单/m.test(source)) {
    errors.push('缺少验收清单标题')
  }

  REQUIRED_TEXT.forEach(required => {
    if (!source.includes(required)) errors.push(`缺少必填内容：${required}`)
  })

  if (/^##\s+账号与密码(?:\s|$)/mu.test(source)) {
    errors.push('不得设置“账号与密码”二级总表或放置规则模块')
  }

  if (/^统一密码\s*[:：]/mu.test(source)) {
    errors.push('不得使用统一密码；每个测试模块必须单独写明密码')
  }

  const modules = getTestModules(source)
  if (!modules.length) {
    errors.push('最短验收流程必须至少包含一个“###”测试模块')
  }

  modules.forEach(module => {
    const accounts = getCredentialValues(module.body, '账号')
    const passwords = getCredentialValues(module.body, '密码')
    const isAnonymousModule = module.heading.includes('匿名')

    if (isAnonymousModule) {
      if (module.heading.includes('一次登录')) {
        errors.push(`匿名测试模块“${module.heading}”不得标记为一次登录`)
      }

      if (accounts.length || passwords.length) {
        errors.push(`匿名测试模块“${module.heading}”不得填写账号或密码`)
      }

      return
    }

    if (!module.heading.includes('一次登录')) {
      errors.push(`测试模块“${module.heading}”必须明确一次登录`)
    }

    if (accounts.length !== 1 || INVALID_ACCOUNT.test(accounts[0] || '')) {
      errors.push(`测试模块“${module.heading}”必须且只能填写一个明确账号`)
    }

    if (passwords.length !== 1) {
      errors.push(`测试模块“${module.heading}”必须且只能填写一个密码`)
    } else if (!SIMPLE_PASSWORD.test(passwords[0])) {
      errors.push(`测试模块“${module.heading}”的密码必须为 8 至 16 位英文字母和数字，并同时包含字母与数字`)
    }
  })

  const allAccounts = getCredentialValues(source, '账号')
  const allPasswords = getCredentialValues(source, '密码')
  const moduleAccountCount = modules.reduce((total, module) => total + getCredentialValues(module.body, '账号').length, 0)
  const modulePasswordCount = modules.reduce((total, module) => total + getCredentialValues(module.body, '密码').length, 0)

  if (allAccounts.length !== moduleAccountCount || allPasswords.length !== modulePasswordCount) {
    errors.push('账号和密码只能写在各自对应的测试模块内')
  }

  if (!/^目标 PR\s*[:：]\s*(?:#\d+|https:\/\/github\.com\/[^\s]+\/pull\/\d+)\s*$/mu.test(source)) {
    errors.push('本地验收包必须绑定目标 PR 编号或 GitHub PR 链接')
  }

  if (!/^目标提交\s*[:：]\s*[0-9a-f]{7,40}\s*$/imu.test(source)) {
    errors.push('本地验收包必须绑定目标 PR 的精确 head commit')
  }

  return errors
}

const runGit = (args, cwd) => spawnSync('git', args, {
  cwd,
  encoding: 'utf8',
  windowsHide: true
})

export const validateAcceptancePackFile = (filePath, cwd = process.cwd()) => {
  const absolutePath = resolve(cwd, filePath)
  if (!existsSync(absolutePath)) return [`验收包不存在：${filePath}`]

  const errors = validateAcceptancePackText(readFileSync(absolutePath, 'utf8'))
  const relativePath = relative(cwd, absolutePath)
  const tracked = runGit(['ls-files', '--error-unmatch', '--', relativePath], cwd)
  if (tracked.status === 0) errors.push('验收包含账号密码，不得被 Git 跟踪')

  const ignored = runGit(['check-ignore', '-q', '--', relativePath], cwd)
  if (ignored.status !== 0) errors.push('验收包必须位于 Git 忽略路径')

  return errors
}

const isDirectRun = process.argv[1]
  && resolve(process.argv[1]) === fileURLToPath(import.meta.url)

if (isDirectRun) {
  const filePath = process.argv.slice(2).find(argument => !argument.startsWith('-'))
    || 'tmp/验收清单.md'
  const allowMissing = process.argv.includes('--allow-missing')

  if (allowMissing && !existsSync(resolve(process.cwd(), filePath))) {
    console.log(`当前没有待验收包：${filePath}`)
    process.exit(0)
  }

  const errors = validateAcceptancePackFile(filePath)
  if (errors.length) {
    console.error('验收包检查失败：')
    errors.forEach(error => console.error(`- ${error}`))
    process.exit(1)
  }

  console.log(`验收包检查通过：${filePath}`)
}
