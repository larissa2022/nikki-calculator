import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REQUIRED_TEXT = [
  '验收批次',
  '目标版本',
  '测试入口',
  '## 账号与密码',
  '## 已准备数据',
  '## 最短验收流程',
  '预期结果',
  '总通过标准',
  '## 异常反馈',
  '## 数据保留与清理'
]

export const validateAcceptancePackText = text => {
  const errors = []
  const source = String(text || '')

  if (!/^# .+验收清单/m.test(source)) {
    errors.push('缺少验收清单标题')
  }

  REQUIRED_TEXT.forEach(required => {
    if (!source.includes(required)) errors.push(`缺少必填内容：${required}`)
  })

  if (!source.includes('一次登录')) {
    errors.push('最短流程必须按账号分组，并明确每个账号一次登录')
  }

  const passwordMatch = source.match(/(?:统一密码|密码)\s*[:：]\s*(\S+)/)
  if (!passwordMatch || /^(?:<.*>|待填写|沿用|见.*|无)$/u.test(passwordMatch[1])) {
    errors.push('本地验收包必须明确可用的测试密码')
  }

  if (!/账号\s*[:：]|\|\s*账号\s*\|/u.test(source)) {
    errors.push('本地验收包必须明确测试账号')
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
