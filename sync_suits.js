import { createClient } from '@supabase/supabase-js'
import fs from 'fs'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// 🌟 1. 初始化配置
const supabaseUrl = 'https://fopyjewbsvusftpqbtml.supabase.co'; // 记得替换
const supabaseServiceKey = 'sb_secret_H2aR4JgUBKs1SBs5O71FXg_B9caBkaH'; // 记得替换

const supabase = createClient(supabaseUrl, supabaseServiceKey)

async function syncSuits() {
  console.log('🚀 开始【标点修正 + 光速打包】同步任务...')

  try {
    const jsonPath = join(__dirname, 'suits_ultimate.json')
    const rawData = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'))

    console.log('⏳ 正在拉取全量衣柜数据...');

    // 🌟 2. 拉取全量数据 (select * 保证 Upsert 绝对安全)
    const [{ data: suits }, { data: existingClothes }] = await Promise.all([
      supabase.from('suits').select('id, name'),
      supabase.from('clothes').select('*') 
    ])

    const suitMap = new Map(suits?.map(s => [s.name.trim(), s.id]) || [])
    
    // 🌟 3. 构建超级精准的 Map，键为: "原味编号|纯横杠分类"
    const clothMap = new Map()
    existingClothes?.forEach(c => {
      if (!c.game_id || c.game_id === 'N') return; 
      
      // 数据库里是 "饰品-头饰-发饰"，为了保险，把所有的 · 都强制转成 -
      const normCat = c.category ? c.category.replace(/·/g, '-').trim() : '';
      
      // 例如键名变成: "019|饰品-头饰-发饰"
      clothMap.set(`${c.game_id.trim()}|${normCat}`, c);
    })

    const payloads = []
    let accCount = 0; 

    // 🌟 4. 完美匹配逻辑
    for (const [suitName, categoriesObj] of Object.entries(rawData)) {
      const suitId = suitMap.get(suitName.trim());
      if (!suitId) continue; 

      for (const [fineCategory, gameIds] of Object.entries(categoriesObj)) {
        // 🚨 核心杀手锏：把 JSON 里的 "饰品-头饰·发饰" 翻译成 "饰品-头饰-发饰"
        const cleanCategory = fineCategory.replace(/·/g, '-').trim();

        for (const gameId of gameIds) {
          // 拿着翻译好的键去匹配
          const lookupKey = `${gameId.trim()}|${cleanCategory}`;
          const targetCloth = clothMap.get(lookupKey);

          if (targetCloth) {
            if (cleanCategory.includes('饰品')) accCount++;

            // 继承原有所有属性，只打上套装烙印！
            payloads.push({
              ...targetCloth,        
              suit_id: suitId,       
              category: cleanCategory // 顺手把分类彻底统一成横杠格式
            })
          }
        }
      }
    }

    if (payloads.length === 0) {
      console.log('⚠️ 还是没有匹配到衣服！请检查标点符号修正后是否和数据库一致。');
      return;
    }

    console.log(`📦 标点修正成功！共精准命中 ${payloads.length} 件部件 (其中饰品 ${accCount} 件)！`)
    console.log('🚛 发车！光速打包写入中...')

    // 🌟 5. 终极打包发送 (一秒完事)
    const CHUNK_SIZE = 500 
    for (let i = 0; i < payloads.length; i += CHUNK_SIZE) {
      const batch = payloads.slice(i, i + CHUNK_SIZE)
      
      const { error } = await supabase.from('clothes')
        .upsert(batch, { onConflict: 'id' }) 
      
      if (error) {
        console.error(`❌ 第 ${Math.floor(i/CHUNK_SIZE) + 1} 批写入失败:`, error.message)
        return;
      }
      
      console.log(`✅ 写入进度: ${Math.min(i + CHUNK_SIZE, payloads.length)} / ${payloads.length}`)
    }

    console.log('✨ 【任务圆满完成】这回真的是天衣无缝了！')

  } catch (err) {
    console.error('💥 脚本运行崩溃:', err.message)
  }
}

syncSuits()