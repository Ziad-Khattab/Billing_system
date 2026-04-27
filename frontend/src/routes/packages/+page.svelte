<script>
  import { fade, fly } from 'svelte/transition';
  import { page } from '$app/state';
  import { showToast } from '$lib/toast.svelte.js';
  import { authState } from '$lib/auth.svelte.js';
  import Modal from '$lib/components/Modal.svelte';
  let plans = $state([]);
  let servicePkgs = $state([]);
  let loading = $state(true);
  let activeIndex = $state(1); // Default to Gold
  let interval;
  let provisionLoading = $state(false);
  let showAdminModal = $state(false);
  let selectedPkg = $state(null);
  let adminTargetMsisdn = $state('');

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

  async function buyBundle(pkg) {
    if (!authState.initialized) return;
    
    if (!authState.user) {
      window.location.href = '/login?returnTo=/packages';
      return;
    }

    if (authState.user.role === 'admin') {
      selectedPkg = pkg;
      showAdminModal = true;
      return;
    }

    // Customer flow
    executePurchase(null, pkg.id);
  }

  async function adminProvision() {
    if (!adminTargetMsisdn) return showToast('Please enter an MSISDN', 'error');
    provisionLoading = true;
    try {
      const contractRes = await fetch(`/api/admin/contracts`);
      const contracts = await contractRes.json();
      const contract = contracts.find(c => c.msisdn === adminTargetMsisdn);
      
      if (!contract) return showToast('No active contract found for this MSISDN', 'error');
      
      executePurchase(contract.id, selectedPkg.id, true);
    } catch (e) {
      showToast('Error finding customer', 'error');
    } finally {
      provisionLoading = false;
    }
  }

  async function executePurchase(contractId, pkgId, isAdmin = false) {
    const url = isAdmin ? '/api/admin/addons' : '/api/customer/addons';
    const body = isAdmin ? { contractId, servicePackageId: pkgId } : { servicePackageId: pkgId };

    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      const data = await res.json();
      if (res.ok) {
        showToast(data.message || 'Provisioning successful!');
        showAdminModal = false;
        adminTargetMsisdn = '';
      } else {
        showToast(data.message || 'Action failed', 'error');
      }
    } catch (e) {
      showToast('Connection error', 'error');
    }
  }


  function startCycle() {
    stopCycle();
    interval = setInterval(() => {
      if (plans.length > 0) {
        activeIndex = (activeIndex + 1) % plans.length;
      }
    }, 6000);
  }

  function stopCycle() {
    if (interval) clearInterval(interval);
  }

  function handleMouseMove(e, id) {
    const card = document.getElementById(id);
    if (!card) return;
    const rect = card.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    card.style.setProperty('--mouse-x', `${x}px`);
    card.style.setProperty('--mouse-y', `${y}px`);
  }

  function navigate(dir) {
    stopCycle();
    if (dir === 'next') {
      activeIndex = (activeIndex + 1) % plans.length;
    } else {
      activeIndex = (activeIndex - 1 + plans.length) % plans.length;
    }
    startCycle();
  }

  $effect(() => {
    loadData();
    startCycle();
    return () => stopCycle();
  });
</script>

<svelte:head>
  <title>Packages — FMRZ</title>
</svelte:head>

<div class="container">

  <Modal 
    bind:show={showAdminModal} 
    title="Provision Package" 
    subtitle="Assign {selectedPkg?.name} to a customer"
    type="admin"
  >
    <div class="form-group">
      <label class="label" for="msisdn">Target MSISDN</label>
      <input 
        type="text" 
        id="msisdn" 
        placeholder="e.g. 01012345678" 
        bind:value={adminTargetMsisdn} 
        class="input"
      />
    </div>
    <div style="display:flex; gap: 1rem; margin-top: 2rem;">
      <button class="btn btn-secondary" style="flex:1" onclick={() => showAdminModal = false}>Cancel</button>
      <button class="btn btn-primary" style="flex:1" onclick={adminProvision} disabled={provisionLoading}>
        {provisionLoading ? 'Processing...' : 'Confirm Provision'}
      </button>
    </div>
  </Modal>

  <div class="page-header">
    <div>
      <h1>Rate Plans & <span class="text-gradient">Packages</span></h1>
      <p class="page-subtitle">Premium communication solutions tailored for the digital age</p>
    </div>
  </div>

  {#if loading}
    <div class="loading">Loading...</div>
  {:else}
    <!-- ─── NEBULA SWITCHER ─── -->
    <h2 class="section-title"><span class="text-gradient">Explore</span> Rate Plans</h2>

    <div class="nebula-outer">
      <button class="nav-arrow prev" onclick={() => navigate('prev')} aria-label="Previous">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>
      </button>

      <div class="nebula-wrapper">
        <div class="nebula-tabs">
          {#each plans as plan, i}
            <button class="tab-btn" class:active={activeIndex === i} onclick={() => { activeIndex = i; startCycle(); }}>
              {plan.name}
            </button>
          {/each}
          <div class="tab-pill" style="transform: translateX({activeIndex * 100}%);"></div>
        </div>

        {#key activeIndex}
          <div 
            id="focus-card"
            class="focus-card card"
            style="--glow-color: {plans[activeIndex]?.name.includes('Basic') ? 'rgba(0, 150, 255, 0.25)' : plans[activeIndex]?.name.includes('Elite') ? 'rgba(255, 165, 0, 0.25)' : 'rgba(224, 8, 0, 0.2)'};"
            onmousemove={(e) => handleMouseMove(e, 'focus-card')}
            in:fly={{ x: 50, duration: 800, opacity: 0 }}
          >
            <div class="glow-layer"></div>
            
            <div class="badge-container">
              {#if activeIndex === 1}
                <div class="plan-badge shimmer-pill popular">⭐ Most Popular</div>
              {:else if plans[activeIndex]?.name.includes('Elite')}
                <div class="plan-badge shimmer-pill elite-pill">⚡ Enterprise Grade</div>
              {:else}
                <div class="badge-spacer"></div>
              {/if}
            </div>

            <div class="card-content-grid">
              <div class="card-visual-side">
                <div class="plan-header">
                  <h3>{plans[activeIndex]?.name}</h3>
                  <div class="plan-price">
                    <span class="currency">EGP</span>
                    <span class="amount">{plans[activeIndex]?.price}</span>
                    <span class="period">/mo</span>
                  </div>
                </div>
                <button
                  onclick={() => {
                    if (!authState.user) window.location.href = '/register?plan=' + plans[activeIndex]?.id;
                    else if (authState.user.role === 'admin') window.location.href = '/admin/contracts';
                    else window.location.href = '/profile';
                  }}
                  class="btn btn-primary"
                  style="width: 100%; margin-top: 2rem; position: relative; z-index: 2;"
                >
                  {#if !authState.initialized}
                    Checking Status...
                  {:else if !authState.user}
                    Activate Now
                  {:else if authState.user.role === 'admin'}
                    Manage Contracts
                  {:else}
                    Back to Dashboard
                  {/if}
                </button>
              </div>

              <div class="card-info-side">
                <div class="plan-details">
                  <div class="detail-row">
                    <span class="detail-label">
                      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="accent-icon"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l2.28-2.28a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
                      Voice Rate
                    </span>
                    <span class="detail-value">{plans[activeIndex]?.ror_voice} <small>EGP/min</small></span>
                  </div>
                  <div class="detail-row">
                    <span class="detail-label">
                      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="accent-icon"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
                      Data Rate
                    </span>
                    <span class="detail-value">{plans[activeIndex]?.ror_data} <small>EGP/MB</small></span>
                  </div>
                  <div class="detail-row">
                    <span class="detail-label">
                      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="accent-icon"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
                      SMS Rate
                    </span>
                    <span class="detail-value">{plans[activeIndex]?.ror_sms} <small>EGP/msg</small></span>
                  </div>
                  <div class="detail-row">
                    <span class="detail-label">
                      <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="accent-icon"><rect x="2" y="5" width="20" height="14" rx="2"/><line x1="2" y1="10" x2="22" y2="10"/></svg>
                      Monthly Fee
                    </span>
                    <span class="detail-value">EGP {plans[activeIndex]?.price}</span>
                  </div>
                </div>
                <div class="description-container">
                  <p class="nebula-description">
                    Optimized for {plans[activeIndex]?.name === 'Basic' ? 'daily essential use' : activeIndex === 1 ? 'maximum value and speed' : 'uncompromising elite performance'}.
                  </p>
                </div>
              </div>
            </div>
          </div>
        {/key}

        <div class="nebula-dots">
          {#each plans as _, i}
            <button 
              class="dot" 
              class:active={activeIndex === i}
              onclick={() => { activeIndex = i; startCycle(); }}
              aria-label="Plan {i + 1}"
            ></button>
          {/each}
        </div>
      </div>

      <button class="nav-arrow next" onclick={() => navigate('next')} aria-label="Next">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>
      </button>
    </div>

    <!-- ─── BUNDLES 2.0 ─── -->
    {#if servicePkgs.length > 0}
      <h2 class="section-title" style="margin-top: 8rem;"><span class="text-gradient">Add-On</span> Bundles</h2>
      <div class="bundles-grid">
        {#each servicePkgs as pkg, i}
          <div 
            id="pkg-card-{i}"
            class="bundle-card card animate-fade" 
            style="animation-delay: {i * 0.1}s; --glow-color: rgba(224, 8, 0, 0.15);"
            onmousemove={(e) => handleMouseMove(e, `pkg-card-${i}`)}
          >
            <div class="glow-layer"></div>
            
            <div class="badge-container">
              {#if pkg.is_roaming}
                <div class="plan-badge shimmer-pill roaming-pill">🌍 Roaming Ready</div>
              {:else if pkg.price > 200}
                <div class="plan-badge shimmer-pill elite-pill">⚡ Ultimate</div>
              {:else if pkg.price < 50}
                <div class="plan-badge shimmer-pill deal-pill">🎁 Best Value</div>
              {:else}
                <div class="plan-badge shimmer-pill trend-pill">🔥 Trending</div>
              {/if}
            </div>

            <div class="bundle-visual">
               <div class="icon-orb" class:rotate={pkg.type === 'data'} class:vibrate={pkg.type === 'voice'}>
                  {#if pkg.type === 'data'}
                    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
                  {:else if pkg.type === 'voice'}
                    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l2.28-2.28a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
                  {:else}
                    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
                  {/if}
               </div>
               <div class="gauge-container">
                  <div class="gauge-track"></div>
                  <div class="gauge-fill" style="width: {Math.min(100, (pkg.amount / (pkg.type === 'data' ? 5000 : 1000)) * 100)}%;"></div>
               </div>
            </div>

            <div class="plan-header" style="text-align: left; margin-bottom: 1rem;">
              <h4 style="font-size: 1.4rem; font-weight: 800; color: white; margin-bottom: 0.5rem; letter-spacing: -0.04em;">{pkg.name}</h4>
              <div class="plan-price" style="justify-content: flex-start; gap: 0.2rem;">
                <span class="amount" style="font-size: 2.4rem;">{pkg.price}</span>
                <span class="period" style="font-size: 0.8rem; color: #94a3b8;">EGP / mo</span>
              </div>
            </div>

            <div class="quota-text">
               <span class="quota-val">{pkg.amount}</span>
               <span class="quota-unit">{pkg.type === 'data' ? 'MB' : pkg.type === 'voice' ? 'Min' : 'SMS'}</span>
            </div>

            <button 
              onclick={() => buyBundle(pkg)}
              class="btn btn-bundle-action" 
              style="width: 100%; margin-top: 2rem;"
            >
              {#if !authState.initialized}
                ...
              {:else if !authState.user}
                Login to Buy
              {:else if authState.user.role === 'admin'}
                Provision for Customer
              {:else}
                Add to Plan
              {/if}
            </button>
          </div>
        {/each}
      </div>
    {/if}
  {/if}
</div>

<style>

  .nebula-outer { display: flex; align-items: center; justify-content: center; gap: 2rem; max-width: 1200px; margin: 0 auto; }
  .nav-arrow { width: 56px; height: 56px; border-radius: 50%; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1); color: white; cursor: pointer; display: flex; align-items: center; justify-content: center; transition: all 0.3s; backdrop-filter: blur(10px); }
  .nav-arrow:hover { background: rgba(224, 8, 0, 0.2); border-color: var(--red); transform: scale(1.1); }
  .nebula-wrapper { flex: 1; max-width: 900px; display: flex; flex-direction: column; align-items: center; gap: 2.5rem; }
  .nebula-tabs { display: flex; position: relative; background: rgba(255, 255, 255, 0.03); padding: 6px; border-radius: 100px; border: 1px solid rgba(255, 255, 255, 0.08); }
  .tab-btn { position: relative; z-index: 2; padding: 10px 24px; background: none; border: none; color: #94a3b8; font-weight: 700; cursor: pointer; transition: color 0.4s; width: 140px; }
  .tab-btn.active { color: white; }
  .tab-pill { position: absolute; top: 6px; left: 6px; height: calc(100% - 12px); width: 140px; background: linear-gradient(135deg, var(--red), var(--red-light)); border-radius: 100px; z-index: 1; transition: transform 0.6s cubic-bezier(0.16, 1, 0.3, 1); box-shadow: 0 4px 15px rgba(224, 8, 0, 0.3); }

  .focus-card {
    width: 100%; min-height: 440px; padding: 4rem;
    background: rgba(15, 15, 25, 0.65); backdrop-filter: blur(25px);
    border-radius: 32px; border: 1px solid rgba(255, 255, 255, 0.1);
    box-shadow: inset 0 1px 1px rgba(255, 255, 255, 0.1), 0 40px 80px rgba(0, 0, 0, 0.5);
    position: relative; overflow: hidden;
    backface-visibility: hidden; transform-style: preserve-3d; will-change: transform;
  }
  .card-content-grid { display: grid; grid-template-columns: 1fr 1.1fr; gap: 4rem; position: relative; z-index: 2; }
  .card-info-side { border-left: 1px solid rgba(255,255,255,0.08); padding-left: 4rem; display: flex; flex-direction: column; justify-content: center; }

  .glow-layer { position: absolute; inset: 0; pointer-events: none; background: radial-gradient(700px circle at var(--mouse-x, 50%) var(--mouse-y, 50%), var(--glow-color), transparent 80%); opacity: 0; transition: opacity 0.4s; z-index: 1; }
  .focus-card .glow-layer { opacity: 0.8; }
  .bundle-card:hover .glow-layer { opacity: 1; }

  .plan-header h3 { font-size: 3rem; font-weight: 900; color: white; margin-bottom: 0.5rem; letter-spacing: -0.06em; }
  .amount { font-size: 5rem; font-weight: 950; background: linear-gradient(135deg, var(--red), var(--red-light)); background-clip: text; -webkit-background-clip: text; -webkit-text-fill-color: transparent; line-height: 1; }

  .plan-details { display: flex; flex-direction: column; gap: 1.5rem; margin-bottom: 2.5rem; }
  .detail-row { display: flex; justify-content: space-between; align-items: center; font-size: 1.1rem; }
  .detail-label { display: flex; align-items: center; gap: 12px; color: #94a3b8; font-weight: 500; }
  .detail-value { color: white; font-weight: 800; }
  .accent-icon { filter: drop-shadow(0 0 5px rgba(224, 8, 0, 0.4)); }

  .description-container { padding-top: 1.5rem; border-top: 1px solid rgba(255,255,255,0.05); }
  .nebula-description { font-size: 1.1rem; color: #94a3b8; line-height: 1.6; letter-spacing: 0.01em; }

  .nebula-dots { display: flex; gap: 12px; margin-top: 2rem; }
  .dot { width: 10px; height: 10px; border-radius: 50%; background: rgba(255, 255, 255, 0.1); border: none; cursor: pointer; transition: all 0.4s; }
  .dot.active { background: var(--red); transform: scale(1.3); box-shadow: 0 0 10px rgba(224, 8, 0, 0.5); }

  /* ── Enhanced Shimmer Pills ── */
  .badge-container { display: flex; justify-content: center; align-items: center; height: 40px; margin-bottom: 0.5rem; position: relative; z-index: 2; }
  .shimmer-pill {
    padding: 6px 20px; border-radius: 100px; font-size: 0.75rem; font-weight: 900;
    text-transform: uppercase; color: white; letter-spacing: 0.05em;
    backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px);
    border: 1px solid rgba(255, 255, 255, 0.1);
    background: rgba(255, 255, 255, 0.05);
    position: relative; overflow: hidden;
    animation: badge-pulse 3s infinite alternate;
  }
  .shimmer-pill::after {
    content: ''; position: absolute; top: 0; left: -100%; width: 50%; height: 100%;
    background: linear-gradient(to right, transparent, rgba(255,255,255,0.2), transparent);
    transform: skewX(-20deg); animation: shimmer-move 4s infinite;
  }
  @keyframes shimmer-move { to { left: 200%; } }
  @keyframes badge-pulse { from { box-shadow: 0 0 5px transparent; } to { box-shadow: 0 0 15px rgba(255, 255, 255, 0.1); } }

  .popular { border-color: rgba(224, 8, 0, 0.4); background: rgba(224, 8, 0, 0.1); }
  .elite-pill { border-color: rgba(139, 92, 246, 0.4); background: rgba(139, 92, 246, 0.1); }
  .roaming-pill { border-color: rgba(59, 130, 246, 0.4); background: rgba(59, 130, 246, 0.1); }
  .deal-pill { border-color: rgba(16, 185, 129, 0.4); background: rgba(16, 185, 129, 0.1); }
  .trend-pill { border-color: rgba(239, 68, 68, 0.4); background: rgba(239, 68, 68, 0.1); }

  .bundles-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2rem; max-width: 1200px; margin: 0 auto; }
  .bundle-card { 
    padding: 2.5rem; border-radius: 28px; 
    background: rgba(255, 255, 255, 0.03); 
    backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
    border: 1px solid rgba(255, 255, 255, 0.08); 
    box-shadow: inset 0 1px 1px rgba(255, 255, 255, 0.1); 
    position: relative; overflow: hidden; 
    transition: all 0.5s cubic-bezier(0.16, 1, 0.3, 1);
    
    /* Anti-Blur Fixes */
    backface-visibility: hidden;
    -webkit-backface-visibility: hidden;
    transform-style: preserve-3d;
    will-change: transform;
    -webkit-font-smoothing: antialiased;
  }
  .bundle-card:hover { 
    transform: translateY(-10px) scale(1.02); 
    border-color: rgba(255, 255, 255, 0.2);
    box-shadow: 0 30px 60px rgba(0, 0, 0, 0.4);
  }

  .bundle-visual { display: flex; align-items: center; gap: 1.5rem; margin-bottom: 1.5rem; position: relative; z-index: 2; }
  .icon-orb { width: 50px; height: 50px; background: rgba(255,255,255,0.05); border-radius: 50%; display: flex; align-items: center; justify-content: center; border: 1px solid rgba(255,255,255,0.1); }
  .icon-orb svg { filter: drop-shadow(0 0 5px rgba(224, 8, 0, 0.3)); }

  .gauge-container { flex: 1; height: 6px; position: relative; background: rgba(255,255,255,0.05); border-radius: 10px; overflow: hidden; }
  .gauge-fill { height: 100%; background: linear-gradient(to right, var(--red), var(--red-light)); border-radius: 10px; transition: width 1s cubic-bezier(0.16, 1, 0.3, 1); }

  .quota-text { display: flex; align-items: baseline; gap: 0.5rem; margin-bottom: 0.5rem; position: relative; z-index: 2; }
  .quota-val { font-size: 1.8rem; font-weight: 800; color: white; }
  .quota-unit { color: #94a3b8; font-weight: 600; font-size: 0.9rem; }

  .btn-bundle-action { background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255,255,255,0.1); color: white; font-weight: 700; padding: 12px; border-radius: 12px; transition: all 0.3s; position: relative; z-index: 2; }
  .bundle-card:hover { border-color: var(--red); }
  .bundle-card:hover .btn-bundle-action { background: var(--red); border-color: var(--red); box-shadow: 0 10px 20px rgba(224, 8, 0, 0.3); }

  .section-title { text-align: center; font-size: 3.5rem; font-weight: 900; margin-bottom: 4rem; color: white; letter-spacing: -0.05em; }

  @media (max-width: 900px) {
    .nebula-outer { flex-direction: column; }
    .card-content-grid { grid-template-columns: 1fr; gap: 2rem; }
    .card-info-side { border-left: none; padding-left: 0; padding-top: 2rem; border-top: 1px solid rgba(255,255,255,0.1); }
  }
</style>