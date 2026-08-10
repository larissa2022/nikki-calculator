<script setup>
import { reactive } from 'vue'

const imageFailures = reactive({ wechat: false, alipay: false })
const channels = [
  { key: 'wechat', name: '微信', image: '/donation/wechat-qr.png', accent: 'wechat' },
  { key: 'alipay', name: '支付宝', image: '/donation/alipay-qr.png', accent: 'alipay' }
]
</script>

<template>
  <section class="donation-page" aria-labelledby="donation-title">
    <header>
      <p>VOLUNTARY SUPPORT</p>
      <h2 id="donation-title">打赏支持</h2>
      <strong>项目将继续免费使用，打赏完全自愿。</strong>
      <span>打赏资金主要用于服务器、域名、存储和日常维护。</span>
    </header>

    <div class="channel-grid">
      <article v-for="channel in channels" :key="channel.key" :class="channel.accent">
        <div class="channel-title">
          <span>{{ channel.key === 'wechat' ? '💬' : '💙' }}</span>
          <div><small>使用对应应用识别</small><h3>{{ channel.name }}</h3></div>
        </div>
        <div class="qr-frame">
          <img
            v-if="!imageFailures[channel.key]"
            :src="channel.image"
            :alt="`${channel.name}收款二维码`"
            @error="imageFailures[channel.key] = true"
          />
          <div v-else class="qr-missing" role="status">
            <span>二维码尚未配置</span>
            <small>请等待项目负责人提供已确认可公开的收款码</small>
          </div>
        </div>
        <p>移动端可长按保存二维码，再到{{ channel.name }}中识别。</p>
      </article>
    </div>

  </section>
</template>

<style scoped>
.donation-page { max-width: 860px; margin: 0 auto; padding: 10px 0 24px; animation: fadeIn .35s ease; }
header { text-align: center; }
header > p { margin: 0 0 5px; color: #db2777; font-size: 10px; font-weight: 900; letter-spacing: .16em; }
h2 { margin: 0; color: #1e293b; font-size: 28px; font-weight: 900; }
header strong, header span { display: block; }
header strong { margin-top: 9px; color: #7c3aed; font-size: 14px; font-weight: 900; }
header span { margin-top: 5px; color: #64748b; font-size: 11px; font-weight: 700; }
.channel-grid { display: grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap: 18px; margin-top: 24px; }
article { padding: 20px; border: 1px solid #e2e8f0; border-radius: 20px; background: #fff; box-shadow: 0 12px 34px rgba(15,23,42,.07); }
article.wechat { border-top: 4px solid #22c55e; }
article.alipay { border-top: 4px solid #0ea5e9; }
.channel-title { display: flex; align-items: center; gap: 10px; }
.channel-title > span { font-size: 25px; }
.channel-title small { color: #94a3b8; font-size: 9px; font-weight: 800; }
.channel-title h3 { margin: 1px 0 0; color: #334155; font-size: 17px; font-weight: 900; }
.qr-frame { display: grid; aspect-ratio: 1; margin-top: 14px; overflow: hidden; place-items: center; border: 1px dashed #cbd5e1; border-radius: 16px; background: #f8fafc; }
.qr-frame img { display: block; width: 100%; height: 100%; object-fit: contain; }
.qr-missing { display: grid; gap: 6px; padding: 20px; text-align: center; }
.qr-missing span { color: #64748b; font-size: 13px; font-weight: 900; }
.qr-missing small { color: #94a3b8; font-size: 10px; font-weight: 700; line-height: 1.6; }
article > p { margin: 12px 0 0; color: #64748b; font-size: 10px; font-weight: 700; text-align: center; }
@media (max-width: 680px) { .channel-grid { grid-template-columns: 1fr; } }
</style>
