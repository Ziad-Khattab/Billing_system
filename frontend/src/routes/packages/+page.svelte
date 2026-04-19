<script>
  let plans = $state([]);
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
      plans = [
        { id: 1, name: 'Bronze', rorVoice: 0.10, rorData: 0.05, rorSms: 0.02, price: 99 },
        { id: 2, name: 'Silver', rorVoice: 0.08, rorData: 0.03, rorSms: 0.01, price: 199 },
        { id: 3, name: 'Gold', rorVoice: 0.05, rorData: 0.02, rorSms: 0.005, price: 349 }
      ];
    }
    loading = false;
  }

  $effect(() => { loadData(); });
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
    <div class="plans-grid">
      {#each plans as plan, i}
        <div class="plan-card animate-fade" style="animation-delay: {i * 0.1}s" class:featured={i === 1}>
          {#if i === 1}
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
          <div class="plan-features">
            <div class="feature-row">
              <span class="feature-label">Voice</span>
              <span class="feature-value">{plan.rorVoice} EGP/min</span>
            </div>
            <div class="feature-row">
              <span class="feature-label">Data</span>
              <span class="feature-value">{plan.rorData} EGP/MB</span>
            </div>
            <div class="feature-row">
              <span class="feature-label">SMS</span>
              <span class="feature-value">{plan.rorSms} EGP/msg</span>
            </div>
          </div>
          <button 
            onclick={() => window.location.href = document.querySelector('.user-menu') ? '/dashboard' : '/register'}
            class="btn {i === 1 ? 'btn-primary' : 'btn-secondary'}" 
            style="width: 100%;"
          >
            Choose Plan
          </button>
        </div>
      {/each}
    </div>

    {#if servicePkgs.length > 0}
      <h2 class="section-title" style="margin-top: 4rem;">Bundled Service Packages</h2>
      <div class="plans-grid">
        {#each servicePkgs as pkg, i}
          <div class="plan-card animate-fade" style="animation-delay: {i * 0.1}s">
            <div class="plan-header">
              <h3>{pkg.name}</h3>
              <p style="font-size: 0.8rem; color: var(--text-muted); margin-top: -0.5rem; margin-bottom: 1rem;">{pkg.description}</p>
              <div class="plan-price">
                <span class="currency">EGP</span>
                <span class="amount">{pkg.price}</span>
                <span class="period">/mo</span>
              </div>
            </div>
            <div class="plan-features">
              <div class="feature-row">
                <span class="feature-label">Voice</span>
                <span class="feature-value">{pkg.voiceMinutes || 0} Min</span>
              </div>
              <div class="feature-row">
                <span class="feature-label">Data</span>
                <span class="feature-value">{pkg.dataLimit || 0} MB</span>
              </div>
              <div class="feature-row">
                <span class="feature-label">SMS</span>
                <span class="feature-value">{pkg.smsCount || 0} SMS</span>
              </div>
            </div>
            <button 
              onclick={() => window.location.href = document.querySelector('.user-menu') ? '/dashboard' : '/register'}
              class="btn btn-secondary" 
              style="width: 100%;"
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
  .section-title { font-size: 1.5rem; margin-bottom: 2rem; color: var(--text-secondary); text-align: center; }
  .page-subtitle { color: var(--text-secondary); margin-top: 0.5rem; }
  .plans-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1.5rem;
    max-width: 900px;
    margin: 0 auto;
  }
  .plan-card {
    position: relative;
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    padding: 2rem;
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
    transition: all 0.3s ease;
  }
  .plan-card:hover {
    transform: translateY(-4px);
    box-shadow: var(--shadow-lg);
  }
  .plan-card.featured {
    border-color: var(--red);
    box-shadow: var(--shadow-red);
    transform: scale(1.05);
  }
  .plan-card.featured:hover { transform: scale(1.05) translateY(-4px); }
  .plan-badge {
    position: absolute;
    top: -12px;
    left: 50%;
    transform: translateX(-50%);
    background: var(--red);
    color: white;
    padding: 0.25rem 1rem;
    border-radius: 100px;
    font-size: 0.75rem;
    font-weight: 600;
    white-space: nowrap;
  }
  .plan-header { text-align: center; }
  .plan-header h3 {
    font-size: 1.25rem;
    font-weight: 600;
    margin-bottom: 0.75rem;
    color: var(--text-secondary);
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
