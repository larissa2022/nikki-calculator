<script setup>
defineEmits(['open-donate'])
</script>

<template>
  <section class="about-page" aria-labelledby="about-title">
    <p class="eyebrow">ABOUT THE PROJECT</p>
    <h2 id="about-title">关于项目</h2>
    <p class="lead">奇迹暖暖极速搭配器是一个持续维护的免费工具，希望让衣柜整理、关卡搭配和图鉴共建更轻松。</p>

    <div class="about-grid">
      <article>
        <span>🧮</span>
        <h3>免费使用</h3>
        <p>核心计算、衣柜和图鉴功能会继续免费开放，不设置付费解锁。</p>
      </article>
      <article>
        <span>🌱</span>
        <h3>社区共建</h3>
        <p>有效贡献、陪审与报错修正共同维护图鉴质量，并通过可审计积分记录成长。</p>
      </article>
      <article>
        <span>🛠️</span>
        <h3>持续维护</h3>
        <p>服务器、域名、存储和日常维护会产生实际成本，项目会在能力范围内持续优化。</p>
      </article>
    </div>

    <div class="support-callout">
      <div>
        <strong>愿意支持项目继续维护？</strong>
        <p>打赏完全自愿，不影响任何免费功能。</p>
      </div>
      <button type="button" @click="$emit('open-donate')">前往打赏支持</button>
    </div>
  </section>
</template>

<style scoped>
.about-page { max-width: 920px; margin: 0 auto; padding: 10px 0 24px; animation: fadeIn .35s ease; }
.eyebrow { margin: 0 0 5px; color: #7c3aed; font-size: 10px; font-weight: 900; letter-spacing: .16em; }
h2 { margin: 0; color: #1e293b; font-size: 26px; font-weight: 900; }
.lead { max-width: 680px; margin: 10px 0 0; color: #64748b; font-size: 13px; font-weight: 650; line-height: 1.8; }
.about-grid { display: grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap: 14px; margin-top: 24px; }
article { padding: 20px; border: 1px solid #ede9fe; border-radius: 18px; background: linear-gradient(145deg,#fff,#faf5ff); box-shadow: 0 10px 28px rgba(124,58,237,.06); }
article span { font-size: 25px; }
article h3 { margin: 11px 0 0; color: #334155; font-size: 15px; font-weight: 900; }
article p { margin: 7px 0 0; color: #64748b; font-size: 11px; font-weight: 650; line-height: 1.7; }
.support-callout { display: flex; align-items: center; justify-content: space-between; gap: 18px; margin-top: 18px; padding: 18px 20px; border-radius: 18px; background: linear-gradient(135deg,#fdf2f8,#f5f3ff); }
.support-callout strong { color: #6d28d9; font-size: 14px; font-weight: 900; }
.support-callout p { margin: 4px 0 0; color: #64748b; font-size: 11px; font-weight: 700; }
.support-callout button { border: 0; border-radius: 12px; padding: 11px 15px; background: #7c3aed; color: white; font-size: 12px; font-weight: 900; cursor: pointer; }
@media (max-width: 720px) { .about-grid { grid-template-columns: 1fr; } }
@media (max-width: 520px) { .support-callout { align-items: stretch; flex-direction: column; } }
</style>
