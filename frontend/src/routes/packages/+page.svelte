<script>
  let plans = $state([]);
  let currentPlan = $state(0);
  let servicePkgs = $state([]);
  let loading = $state(true);

  async function loadData() {
    try {
      const [plansRes, pkgsRes] = await Promise.all([
        fetch('/api/public/rateplans'),
        fetch('/api/public/service-packages')
      ]);
      if (plansRes.ok) plans = await plansRes.json();
      if (pkgsRes.ok) servicePkgs = await pkgsRes.json();
    } catch (e) {
      plans = [];
      servicePkgs = [];
    }
    loading = false;
  }

  $effect(() => {
    loadData();
    const interval = setInterval(() => {
      if (plans.length > 0) {
        currentPlan = (currentPlan + 1) % plans.length;
      }
    }, 5000);
    return () => clearInterval(interval);
  });
</script>

<svelte:head>
  <title>Packages — FMRZ</title>
</svelte:head>

<div class="container">
  <div class="page-header">
    <div>
      <h1>Rate Plans & <span class="text-gradient">Packages</span></h1>
      <p class="page-subtitle">Choose the perfect plan for your communication needs</p>
    </div>
  </div>

  {#if loading}
    <div class="loading">Loading...</div>
  {:else}
    <!-- ─── RATE PLANS ─── -->
    <h2 class="section-title">Standard Rate Plans</h2>

    <div class="plan-stack-wrapper">
      <div class="plan-stack">
        {#each plans as plan, i}
          {@const offset = (i - currentPlan + plans.length) % plans.length}
          <div
                  class="plan-card stack-card card"
                  class:active={offset === 0}
                  style="--offset: {offset}"
          >
            {#if i === 1}
              <div class="plan-badge popular">⭐ Most Popular</div>
            {/if}

            <div class="plan-header">
              <h3>{plan.name}</h3>
              <div class="plan-price">
                <span class="currency">EGP</span>
                <span class="amount">{plan.price}</span>
                <span class="period">/mo</span>
              </div>
            </div>

            <div class="plan-details">
              <div class="detail-row">
                <span class="detail-label">📞 Voice Rate</span>
                <span class="detail-value">
                  {plan.ror_voice}
                  <small>EGP/min</small>
                </span>
              </div>
              <div class="detail-row">
                <span class="detail-label">🌐 Data Rate</span>
                <span class="detail-value">
                  {plan.ror_data}
                  <small>EGP/MB</small>
                </span>
              </div>
              <div class="detail-row">
                <span class="detail-label">💬 SMS Rate</span>
                <span class="detail-value">
                  {plan.ror_sms}
                  <small>EGP/msg</small>
                </span>
              </div>
              <div class="detail-row">
                <span class="detail-label">💳 Monthly Fee</span>
                <span class="detail-value">
                  EGP {plan.price}
                </span>
              </div>
            </div>

            <button
                    onclick={() => window.location.href = '/register?plan=' + plan.id}
                    class="btn {offset === 0 ? 'btn-primary' : 'btn-secondary'}"
                    style="width: 100%;"
            >
              Choose {plan.name}
            </button>
          </div>
        {/each}
      </div>

      <div class="dots-nav">
        {#each plans as _, i}
          <button
                  class="dot-btn"
                  class:active={currentPlan === i}
                  onclick={() => currentPlan = i}
                  aria-label="Go to plan {i + 1}"
          ></button>
        {/each}
      </div>
    </div>

    <!-- ─── SERVICE PACKAGES ─── -->
    {#if servicePkgs.length > 0}
      <h2 class="section-title" style="margin-top: 5rem;">Bundled Service Packages</h2>
      <div class="bundles-grid">
        {#each servicePkgs as pkg, i}
          <div class="bundle-card card animate-fade" style="animation-delay: {i * 0.1}s">

            {#if pkg.is_roaming}
              <div class="plan-badge roaming">🌍 Roaming Ready</div>
            {:else if pkg.price === 0 || pkg.price === null}
              <div class="plan-badge promo">🎁 Exclusive Deal</div>
            {:else if i === 0}
              <div class="plan-badge trend">🔥 Trending</div>
            {/if}

            <div class="plan-header">
              <h3>{pkg.name}</h3>
              <p class="pkg-subtitle">{pkg.description ?? ''}</p>
              {#if pkg.price !== null}
                <div class="plan-price">
                  <span class="currency">EGP</span>
                  <span class="amount">{pkg.price}</span>
                  <span class="period">per month</span>
                </div>
              {/if}
            </div>

            <div class="plan-features">
              {#if pkg.type === 'voice'}
                <div class="feature-row">
                  <div class="feature-label-group">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"
                         viewBox="0 0 24 24" fill="none" stroke="currentColor"
                         stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"
                         style="color: #3B82F6">
                      <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0
                               1-8.63-3.07A19.5 19.5 0 0 1 5.19 12.9a19.79 19.79
                               0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2
                               1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45
                               2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0
                               0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1
                               22 16.92z"/>
                    </svg>
                    <span>Voice</span>
                  </div>
                  <span class="feature-value">{pkg.amount} Min</span>
                </div>

              {:else if pkg.type === 'data'}
                <div class="feature-row">
                  <div class="feature-label-group">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"
                         viewBox="0 0 24 24" fill="none" stroke="currentColor"
                         stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"
                         style="color: #A855F7">
                      <circle cx="12" cy="12" r="10"/>
                      <path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/>
                      <path d="M2 12h20"/>
                    </svg>
                    <span>Data</span>
                  </div>
                  <span class="feature-value">{pkg.amount} MB</span>
                </div>

              {:else if pkg.type === 'sms'}
                <div class="feature-row">
                  <div class="feature-label-group">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"
                         viewBox="0 0 24 24" fill="none" stroke="currentColor"
                         stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"
                         style="color: #F59E0B">
                      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
                    </svg>
                    <span>SMS</span>
                  </div>
                  <span class="feature-value">{pkg.amount} Msg</span>
                </div>

              {:else if pkg.type === 'free_units'}
                <div class="feature-row">
                  <div class="feature-label-group">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"
                         viewBox="0 0 24 24" fill="none" stroke="currentColor"
                         stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"
                         style="color: #22C55E">
                      <polyline points="20 6 9 17 4 12"/>
                    </svg>
                    <span>Free Units</span>
                  </div>
                  <span class="feature-value">{pkg.amount} Units</span>
                </div>
              {/if}

              <div class="feature-row">
                <div class="feature-label-group">
                  <span style="color: var(--text-muted)">Priority</span>
                </div>
                <span class="feature-value" style="color: var(--text-muted)">
                  {pkg.priority === 1 ? '⚡ High' : '📦 Standard'}
                </span>
              </div>
            </div>

            <button
                    onclick={() => window.location.href = '/register?pkg=' + pkg.id}
                    class="btn btn-secondary"
                    style="width: 100%; margin-top: 1.5rem;"
            >
              Choose Package
            </button>
          </div>
        {/each}
      </div>
    {/if}
  {/if}
</div>

<style>
  /* ── Stack carousel ── */
  .plan-stack-wrapper {
    position: relative;
    max-width: 1000px;
    margin: 0 auto 4rem;
    padding: 2rem 0;
  }
  .plan-stack {
    position: relative;
    height: 480px;
    display: flex;
    justify-content: center;
    align-items: center;
    perspective: 1200px;
  }
  .stack-card {
    position: absolute;
    width: 340px;
    height: 460px;
    padding: 2.5rem 2rem;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    transition: all 0.8s cubic-bezier(0.16, 1, 0.3, 1);
    opacity: 0;
    pointer-events: none;
    transform: translateX(100px) scale(0.85) rotateY(-15deg);
    z-index: 1;
    border-radius: var(--radius-lg);
  }
  .stack-card[style*="--offset: 0"] {
    opacity: 1;
    pointer-events: auto;
    transform: translateX(0) scale(1.05) rotateY(0);
    z-index: 10;
    border-color: rgba(224, 8, 0, 0.4);
    box-shadow: 0 40px 100px rgba(0,0,0,0.9), 0 0 40px rgba(224,8,0,0.2);
    background: linear-gradient(135deg,
    rgba(255,255,255,0.12) 0%,
    rgba(255,255,255,0.02) 100%);
  }
  .stack-card[style*="--offset: 1"] {
    opacity: 0.6;
    transform: translateX(280px) scale(0.9) rotateY(-30deg);
    z-index: 5;
  }
  .stack-card[style*="--offset: 2"],
  .stack-card[style*="--offset: -1"] {
    opacity: 0.6;
    transform: translateX(-280px) scale(0.9) rotateY(30deg);
    z-index: 5;
  }

  /* ── Dots nav ── */
  .dots-nav {
    display: flex;
    justify-content: center;
    gap: 12px;
    margin-top: 2rem;
  }
  .dot-btn {
    width: 12px; height: 12px;
    border-radius: 50%;
    background: var(--border);
    border: none;
    cursor: pointer;
    transition: all 0.3s;
  }
  .dot-btn.active {
    background: var(--red);
    transform: scale(1.3);
    box-shadow: 0 0 10px rgba(224,8,0,0.5);
  }
  .dot-btn:hover:not(.active) { background: rgba(255,255,255,0.2); }

  /* ── Plan card internals ── */
  .plan-header { text-align: center; margin-bottom: 1rem; }
  .plan-header h3 {
    font-size: 1.35rem;
    font-weight: 700;
    margin-bottom: 0.5rem;
    background: linear-gradient(135deg, #ffffff 0%, #a5b4fc 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }
  .plan-price {
    display: flex;
    align-items: baseline;
    justify-content: center;
    gap: 0.25rem;
    margin-top: 0.5rem;
  }
  .currency { font-size: 1rem; color: var(--text-muted); font-weight: 500; }
  .amount {
    font-size: 3rem; font-weight: 800;
    background: linear-gradient(135deg, var(--red), var(--red-light));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }
  .period { font-size: 0.9rem; color: var(--text-muted); }

  .plan-details {
    display: flex;
    flex-direction: column;
    gap: 0.6rem;
    padding: 1rem 0;
    border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border);
    flex: 1;
  }
  .detail-row {
    display: flex;
    justify-content: space-between;
    font-size: 0.875rem;
  }
  .detail-label { color: var(--text-muted); }
  .detail-value { color: var(--text-primary); font-weight: 600; }
  .detail-value small { font-weight: 400; color: var(--text-muted); margin-left: 3px; }

  /* ── Badges ── */
  .plan-badge {
    position: absolute;
    top: -16px; right: 20px;
    padding: 6px 16px;
    border-radius: 50px;
    font-size: 0.72rem;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: white;
    z-index: 10;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    white-space: nowrap;
  }
  .plan-badge.popular  { background: linear-gradient(135deg, #E00800, #FF416C); }
  .plan-badge.trend    { background: linear-gradient(135deg, #FF4B2B, #FF416C); box-shadow: 0 4px 15px rgba(255,65,108,0.4); }
  .plan-badge.promo    { background: linear-gradient(135deg, #F59E0B, #D97706); box-shadow: 0 4px 15px rgba(245,158,11,0.4); }
  .plan-badge.roaming  { background: linear-gradient(135deg, #3B82F6, #2563EB); box-shadow: 0 4px 15px rgba(59,130,246,0.4); }

  /* ── Bundles grid ── */
  .bundles-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 2rem;
    max-width: 1100px;
    margin: 3rem auto 0;
    overflow: visible;
  }
  .bundle-card {
    padding: 3.5rem 2rem 2rem;
    display: flex;
    flex-direction: column;
    position: relative;
    overflow: visible;
    transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
  }
  .bundle-card:hover {
    transform: translateY(-8px);
    border-color: var(--red);
    box-shadow: 0 20px 40px rgba(0,0,0,0.4), 0 0 20px rgba(224,8,0,0.15);
  }
  .pkg-subtitle {
    font-size: 0.85rem;
    color: var(--text-muted);
    margin-bottom: 1rem;
    min-height: 2.5rem;
  }

  /* ── Feature rows (bundles) ── */
  .plan-features {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding: 1rem 0;
    border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border);
    flex: 1;
  }
  .feature-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 0.875rem;
  }
  .feature-label-group {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--text-secondary);
    font-weight: 500;
  }
  .feature-value { color: var(--text-primary); font-weight: 600; }

  /* ── Misc ── */
  .section-title {
    text-align: center;
    font-size: 2.25rem;
    font-weight: 800;
    margin-bottom: 3.5rem;
    color: white;
    letter-spacing: -0.02em;
  }
  .page-subtitle { color: var(--text-secondary); margin-top: 0.5rem; }
  .loading { text-align: center; padding: 4rem; color: var(--text-muted); }
  .text-gradient {
    background: linear-gradient(135deg, var(--red), var(--red-light));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }

  @media (max-width: 768px) {
    .bundles-grid { grid-template-columns: 1fr; }
    .stack-card[style*="--offset: 1"],
    .stack-card[style*="--offset: 2"] { opacity: 0; }
  }
</style>