import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // 1. 处理浏览器的预检请求 (CORS)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

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
                { image: `data:image/png;base64,${imageBase64}` },
                { text: "这张图里有哪些奇迹暖暖的衣服名字？直接返回名字，用中文逗号分隔，不要废话。" }
              ]
            }
          ]
        }
      })
    })

    const aiResult = await response.json()
    // 兼容通义千问的结果提取路径
    const clothesNames = aiResult.output.choices[0].message.content[0].text

    return new Response(JSON.stringify({ names: clothesNames }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400
    })
  }
})