import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const DEV_PROJECT_REF = 'tfwejruvdahonacyldrg'
const refPath = resolve('supabase/.temp/project-ref')

let currentRef = ''

try {
  currentRef = readFileSync(refPath, 'utf8').trim()
} catch {
  console.error(`无法读取 ${refPath}`)
  console.error('请先执行: supabase link --project-ref tfwejruvdahonacyldrg')
  process.exit(1)
}

if (currentRef !== DEV_PROJECT_REF) {
  console.error(`当前 Supabase link 指向 ${currentRef || '(空)'}`)
  console.error(`安全检查失败：数据库开发命令只能指向 dev 项目 ${DEV_PROJECT_REF}`)
  process.exit(1)
}

console.log(`Supabase dev link 检查通过: ${currentRef}`)
