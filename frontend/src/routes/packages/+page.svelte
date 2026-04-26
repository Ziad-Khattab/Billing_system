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
            {#if plan.id === 2}
              <div class="plan-badge">Most Popular</div>
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
                <span class="detail-label">Voice Allowance</span>
                <span class="detail-value">
                  {plan.name === 'Elite Enterprise' ? 'Unlimited' : (plan.name === 'Premium Gold' ? '2000' : '500')} 
                  <small>Minutes</small>
                </span>
              </div>
              <div class="detail-row">
                <span class="detail-label">Data Allowance</span>
                <span class="detail-value">
                  {plan.name === 'Elite Enterprise' ? '50' : (plan.name === 'Premium Gold' ? '10' : '2')} 
                  <small>GB</small>
                </span>
              </div>
              <div class="detail-row">
                <span class="detail-label">SMS Allowance</span>
                <span class="detail-value">
                  {plan.name === 'Elite Enterprise' ? 'Unlimited' : (plan.name === 'Premium Gold' ? '500' : '100')} 
                  <small>Messages</small>
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

    {#if servicePkgs.length > 0}
      <h2 class="section-title" style="margin-top: 5rem;">Bundled Service Packages</h2>
      <div class="bundles-grid">
        {#each servicePkgs as pkg, i}
          <div class="bundle-card card animate-fade" style="animation-delay: {i * 0.1}s">
            {#if pkg.is_roaming}
              <div class="plan-badge roaming">🌍 Roaming Ready</div>
            {:else if pkg.price === 0}
              <div class="plan-badge promo">🎁 Exclusive Deal</div>
            {:else if i === 0}
              <div class="plan-badge trend">🔥 Trending</div>
            {/if}
            
            <div class="plan-header">
              <h3>{pkg.name}</h3>
              <p class="pkg-subtitle">{pkg.description}</p>
              <div class="plan-price">
                <span class="currency">EGP</span>
                <span class="amount">{pkg.price}</span>
                <span class="period">per month</span>
              </div>
            </div>

            <div class="plan-features">
              {#if pkg.voiceAmount > 0}
                <div class="feature-row">
                  <div class="feature-label-group">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="color: #3B82F6"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
                    <span>Voice</span>
                  </div>
                  <span class="feature-value">{pkg.voiceAmount} Min</span>
                </div>
              {/if}
              {#if pkg.dataAmount > 0}
                <div class="feature-row">
                  <div class="feature-label-group">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="color: #A855F7"><circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/></svg>
                    <span>Data</span>
                  </div>
                  <span class="feature-value">{pkg.dataAmount} MB</span>
                </div>
              {/if}
              {#if pkg.smsAmount > 0}
                <div class="feature-row">
                  <div class="feature-label-group">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="color: #F59E0B"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
                    <span>SMS</span>
                  </div>
                  <span class="feature-value">{pkg.smsAmount} Msg</span>
                </div>
              {/if}
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
  .plan-stack-wrapper {
    position: relative;
    max-width: 1000px;
    margin: 0 auto 4rem;
    padding: 2rem 0;
  }
  .plan-stack {
    position: relative;
    height: 450px;
    display: flex;
    justify-content: center;
    align-items: center;
    perspective: 1200px;
  }
  .stack-card {
    position: absolute;
    width: 340px;
    height: 480px;
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
    box-shadow: 0 40px 100px rgba(0,0,0,0.9), 0 0 40px rgba(224, 8, 0, 0.2);
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.12) 0%, rgba(255, 255, 255, 0.02) 100%);
  }
  /* Next Card */
  .stack-card[style*="--offset: 1"] {
    opacity: 0.6;
    transform: translateX(280px) scale(0.9) rotateY(-30deg);
    z-index: 5;
  }
  /* Previous Card */
  .stack-card[style*="--offset: 2"], 
  .stack-card[style*="--offset: -1"] {
    opacity: 0.6;
    transform: translateX(-280px) scale(0.9) rotateY(30deg);
    z-index: 5;
  }

  .dots-nav {
    display: flex;
    justify-content: center;
    gap: 12px;
    margin-top: 2rem;
  }
  .dot-btn {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: var(--border);
    border: none;
    cursor: pointer;
    transition: all 0.3s;
  }
  .dot-btn.active {
    background: var(--red);
    transform: scale(1.3);
    box-shadow: 0 0 10px rgba(224, 8, 0, 0.5);
  }
  .dot-btn:hover:not(.active) { background: rgba(255,255,255,0.2); }

  .section-title {
    text-align: center;
    font-size: 2.25rem;
    font-weight: 800;
    margin-bottom: 3.5rem;
    color: white;
    letter-spacing: -0.02em;
  }
  .page-subtitle { color: var(--text-secondary); margin-top: 0.5rem; }
  .packages-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 2.5rem;
    margin-top: 3rem; /* Extra space for badges */
    overflow: visible;
  }
  .packages-section {
    padding: 6rem 0;
    overflow: visible;
  }
  .plans-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 2.5rem;
    max-width: 1200px;
    margin: 0 auto;
    background: transparent;
    padding: 2rem 0;
  }
  .bundles-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 2rem;
    max-width: 1100px;
    margin: 0 auto;
  }
  .bundle-card {
    padding: 2rem;
    display: flex;
    flex-direction: column;
    transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
    position: relative;
    overflow: visible;
  }
  .bundle-card:hover {
    transform: translateY(-8px);
    border-color: var(--red);
    box-shadow: 0 20px 40px rgba(0,0,0,0.4), 0 0 20px rgba(224, 8, 0, 0.15);
  }
  .pkg-subtitle { font-size: 0.85rem; color: var(--text-muted); margin-bottom: 1.5rem; height: 2.5rem; overflow: hidden; }
  
  .feature-label-group {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--text-secondary);
    font-weight: 500;
  }
  .support-row { margin-top: 0.5rem; padding-top: 1rem; border-top: 1px dashed var(--border); }

  .plan-badge {
    position: absolute;
    top: -12px;
    right: 20px;
    padding: 6px 16px;
    border-radius: 50px;
    font-size: 0.75rem;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: white;
    z-index: 10;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
  }

  .plan-badge.trend { background: linear-gradient(135deg, #FF4B2B, #FF416C); box-shadow: 0 4px 15px rgba(255, 65, 108, 0.4); }
  .plan-badge.promo { background: linear-gradient(135deg, #F59E0B, #D97706); box-shadow: 0 4px 15px rgba(245, 158, 11, 0.4); }
  .plan-badge.roaming { background: linear-gradient(135deg, #3B82F6, #2563EB); box-shadow: 0 4px 15px rgba(59, 130, 246, 0.4); }

  .plan-header h3 {
    font-size: 1.25rem;
    font-weight: 700;
    margin-bottom: 0.5rem;
    background: linear-gradient(135deg, #ffffff 0%, #a5b4fc 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }
  .plan-price { display: flex; align-items: baseline; justify-content: center; gap: 0.25rem; }
  .currency { font-size: 1rem; color: var(--text-muted); font-weight: 500; }
  .amount { font-size: 3rem; font-weight: 800; background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .period { font-size: 0.9rem; color: var(--text-muted); }
  .plan-features {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding: 1rem 0;
    border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border);
  }
  .feature-row {
    display: flex;
    justify-content: space-between;
    font-size: 0.875rem;
  }
  .feature-label { color: var(--text-muted); }
  .feature-value { color: var(--text-primary); font-weight: 500; }
  .loading { text-align: center; padding: 4rem; color: var(--text-muted); }
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  @media (max-width: 768px) { .plans-grid { grid-template-columns: 1fr; } .plan-card.featured { transform: none; } }
</style>
