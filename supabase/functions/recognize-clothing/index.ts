import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
// 🌟 核心修复：把 https://esm.sh... 换成 npm: 前缀，彻底告别 522 报错！
import { createClient } from "npm:@supabase/supabase-js@2"
const corsHeaders = {
  'Access-Control-Allow-Origin': '*', // 允许所有域名访问（本地 localhost 和未来的线上域名）
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS', // 🌟 必须显式允许 OPTIONS 请求
}


serve(async (req) => {
  // 🌟 核心修复点：处理浏览器的 OPTIONS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { 
      headers: corsHeaders,
      status: 200 // 明确告诉浏览器：安全检查通过，你可以发 POST 请求了
    })
  }
  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    // 2. 获取当前登录用户的 ID
    const { data: { user } } = await supabaseClient.auth.getUser()
    if (!user) throw new Error('未授权，请先登录')

    // 3. 🌟 原子操作：检查并扣减 1 次额度
    const { data: hasQuota, error: quotaError } = await supabaseClient
      .rpc('deduct_user_quota', { user_id_param: user.id })

    if (quotaError || !hasQuota) {
      return new Response(JSON.stringify({ error: '额度耗尽，请购买或等待发放哦~' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403
      })
    }

    // 4. 接收 Base64 图片
    const { imageBase64 } = await req.json()

    // 5. 🚀 请求通义千问 Qwen-VL-Plus
    const aliyunApiKey = Deno.env.get('ALIYUN_BAILIAN_API_KEY')
    const response = await fetch('https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${aliyunApiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: "qwen-vl-plus",
        input: {
          messages: [
            {
              role: "user",
              content: [
                // 🌟 核心修复：直接原封不动地把前端传来的完整 base64 字符串塞进去！不要再套模板了！
                { image: imageBase64 },
                { text: "这张图里有哪些奇迹暖暖的衣服名字？直接返回名字，用中文逗号分隔，不要废话。" }
              ]
            }
          ]
        }
      })
    })

    const aiResult = await response.json()
    
    // 🌟 新增：安全气囊，检查阿里云是否报错
    if (aiResult.code || !aiResult.output) {
      throw new Error(`阿里云API拒绝服务: ${aiResult.message || '未知错误'}`)
    }

    // 兼容通义千问的结果提取路径
    const clothesNames = aiResult.output.choices[0].message.content[0].text

    // 成功时的返回
    return new Response(JSON.stringify({ names: clothesNames }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200
    })

  } catch (error) {
    // 🌟 新增这一行：让具体的死因打印在 Supabase 后台日志里
    console.error("❌ AI 识别逻辑出错:", error)

    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400
    })
  }
})