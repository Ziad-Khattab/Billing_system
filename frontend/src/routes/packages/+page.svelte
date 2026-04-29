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
  let searchResults = $state([]);
  let selectedContract = $state(null);
  let showDropdown = $state(false);
  let msisdnSearch = $state('');
  
  // Logical separation for UI layout
  let welcomeGift = $derived(servicePkgs.find(p => p.name.toLowerCase().includes('gift')));
  let addons = $derived(
    servicePkgs
      .filter(p => !p.name.toLowerCase().includes('gift'))
      .sort((a, b) => {
        // Sort by Roaming (Domestic first)
        if (a.is_roaming !== b.is_roaming) return a.is_roaming ? 1 : -1;
        // Sort by Type: Voice(1) -> Data(2) -> SMS(3)
        const typeOrder = { 'voice': 1, 'data': 2, 'sms': 3 };
        return (typeOrder[a.type] || 99) - (typeOrder[b.type] || 99);
      })
  );
  
  // Real-time search effect
  $effect(() => {
    if (msisdnSearch.length >= 2 && !selectedContract) {
      const timer = setTimeout(async () => {
        const res = await fetch(`/api/admin/contracts?search=${encodeURIComponent(msisdnSearch)}`);
        if (res.ok) {
          const data = await res.json();
          searchResults = data.data || [];
          showDropdown = true;
        }
      }, 300);
      return () => clearTimeout(timer);
    } else {
      showDropdown = false;
    }
  });

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
    if (!selectedContract) return showToast('Please select a customer first', 'error');
    provisionLoading = true;
    try {
      executePurchase(selectedContract.id, selectedPkg.id, true);
    } catch (e) {
      showToast('Error provisioning bundle', 'error');
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
        msisdnSearch = '';
        selectedContract = null;
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
    <div class="form-group" style="position: relative;">
      <label class="label">Search Customer / MSISDN</label>
      <input 
        class="input" 
        type="text" 
        bind:value={msisdnSearch} 
        onfocus={() => { if (searchResults.length > 0) showDropdown = true; }}
        onblur={() => setTimeout(() => showDropdown = false, 200)}
        oninput={() => selectedContract = null}
        placeholder="Type MSISDN or Name..." 
      />
      
      {#if showDropdown && searchResults.length > 0}
        <div class="search-results card animate-fade">
          <div class="dropdown-header" style="padding: 8px 16px; font-size: 0.7rem; color: var(--text-muted); border-bottom: 1px solid var(--border); background: rgba(255,255,255,0.02)">
            Top Matches
          </div>
          {#each searchResults as contract}
            {@const pName = (contract.rateplanName || '').toLowerCase()}
            {@const badgeClass = pName.includes('basic') ? 'badge-plan-basic' : pName.includes('premium') ? 'badge-plan-premium' : pName.includes('elite') ? 'badge-plan-elite' : pName.includes('standard') || pName.includes('gold') ? 'badge-plan-standard' : 'badge-customer'}
            <button 
              class="result-item" 
              onclick={() => {
                selectedContract = contract;
                msisdnSearch = `${contract.msisdn} (${contract.customerName})`;
                showDropdown = false;
              }}
            >
              <div style="display:flex; flex-direction:column; gap: 2px;">
                <span class="res-num" style="font-size: 1rem;">{contract.msisdn}</span>
                <span class="res-name" style="font-size: 0.75rem; opacity: 0.7;">{contract.customerName}</span>
              </div>
              <span class="badge {badgeClass}" style="font-size:0.55rem; padding: 2px 8px; height: fit-content; border-radius: 6px;">{contract.rateplanName}</span>
            </button>
          {/each}
        </div>
      {/if}
    </div>
    
    {#if selectedContract}
      <div class="selection-status animate-fade">
        ✅ Selected: <strong>{selectedContract.msisdn}</strong> ({selectedContract.customerName})
      </div>
    {/if}
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
          {@const activePlan = plans[activeIndex]}
          {@const isElite = activePlan?.name?.toLowerCase().includes('elite') || activePlan?.price > 500}
          {@const isBasic = activePlan?.name?.toLowerCase().includes('basic') || activePlan?.price < 100}
          {@const glowColor = isElite ? 'rgba(139, 92, 246, 0.25)' : isBasic ? 'rgba(59, 130, 246, 0.25)' : 'rgba(224, 8, 0, 0.2)'}

          <div 
            id="focus-card"
            class="focus-card card"
            style="--glow-color: {glowColor};"
            onmousemove={(e) => handleMouseMove(e, 'focus-card')}
            in:fly={{ x: 50, duration: 800, opacity: 0 }}
          >
            <div class="glow-layer"></div>

            <div class="badge-container">
              {#if isElite}
                <div class="plan-badge shimmer-pill elite-pill">⚡ Enterprise Grade</div>
              {:else if activeIndex === 1 || activePlan?.name?.toLowerCase().includes('gold') || activePlan?.name?.toLowerCase().includes('premium')}
                <div class="plan-badge shimmer-pill popular">⭐ Most Popular</div>
              {:else if isBasic}
                <div class="plan-badge shimmer-pill basic-pill">🌱 Essential</div>
              {:else}
                <div class="badge-spacer"></div>
                <div class="plan-badge shimmer-pill trend-pill">🔥 Best Value</div>
              {/if}
            </div>

            <div class="card-content-grid">
              <div class="card-visual-side">
                <div class="plan-header">
                  <h3>{activePlan?.name}</h3>
                  <div class="plan-price">
                    <span class="currency">EGP</span>
                    <span class="amount">{activePlan?.price}</span>
                    <span class="period">/mo</span>
                  </div>
                </div>

                <div class="plan-actions" style="margin-top: 2.5rem; display: flex; flex-direction: column; gap: 1rem;">
                  <button
                    onclick={() => {
                      if (!authState.user) window.location.href = '/register?plan=' + activePlan?.id;
                      else if (authState.user.role === 'admin') window.location.href = '/admin/contracts?plan=' + activePlan?.id;
                      else window.location.href = '/onboarding?plan=' + activePlan?.id;
                    }}
                    class="btn btn-primary"
                    style="width: 100%; position: relative; z-index: 2; padding: 1.25rem;"
                  >
                    {#if !authState.initialized}
                      Checking Status...
                    {:else if !authState.user}
                      Get Started Now
                    {:else if authState.user.role === 'admin'}
                      Provision to Customer
                    {:else}
                      Switch to This Plan
                    {/if}
                  </button>

                  <p class="tax-info">Prices exclude 14% VAT. Automatic monthly renewal.</p>
                </div>
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

    <!-- ─── WELCOME GIFT (DEDICATED SECTION) ─── -->
    {#if welcomeGift}
      <div class="welcome-gift-hero animate-fade" style="margin-top: 8rem;">
        <div class="gift-glow"></div>
        <div class="gift-content">
          <div class="gift-tag">One-Time Onboarding Reward</div>
          <div class="gift-main">
            <div class="gift-text">
              <h2>{welcomeGift.name}</h2>
              <p>{welcomeGift.description}</p>
            </div>
            <div class="gift-visual">
              <div class="gift-price-tag">
                <span class="val">FREE</span>
                <span class="sub">0 EGP</span>
              </div>
               <button 
                 onclick={() => buyBundle(welcomeGift)}
                 class="btn btn-gift"
               >
                 {authState.user?.role === 'admin' ? 'Give to Customer' : 'Claim My Gift'}
               </button>
            </div>
          </div>
        </div>
      </div>
    {/if}

    <!-- ─── BUNDLES 2.0 ─── -->
    {#if addons.length > 0}
      <h2 class="section-title" style="margin-top: 6rem;"><span class="text-gradient">Add-On</span> Bundles</h2>
      <div class="bundles-grid">
        {#each addons as pkg, i}
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
    transform: translateZ(0); backface-visibility: hidden; will-change: transform;
    transition: transform 0.5s cubic-bezier(0.16, 1, 0.3, 1);
  }
  .focus-card:hover {
    transform: translateY(-8px) translateZ(0);
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
  .basic-pill { border-color: rgba(59, 130, 246, 0.4); background: rgba(59, 130, 246, 0.1); }
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
    transform: translateY(-10px) translateZ(0); 
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
  .bundle-card:hover { border-color: rgba(255, 255, 255, 0.3); }
  .bundle-card:hover .btn-bundle-action { background: var(--red); border-color: var(--red); box-shadow: 0 10px 20px rgba(224, 8, 0, 0.3); }

  .section-title { text-align: center; font-size: 3.5rem; font-weight: 900; margin-bottom: 4rem; color: white; letter-spacing: -0.05em; }

  @media (max-width: 900px) {
    .nebula-outer { flex-direction: column; }
    .card-content-grid { grid-template-columns: 1fr; gap: 2rem; }
    .card-info-side { border-left: none; padding-left: 0; padding-top: 2rem; border-top: 1px solid rgba(255,255,255,0.1); }
  }
  /* ── Welcome Gift Hero ── */
  .welcome-gift-hero {
    position: relative;
    max-width: 850px;
    margin: 0 auto;
    padding: 1.5rem 2.5rem;
    background: rgba(245, 158, 11, 0.03);
    border: 1px solid rgba(245, 158, 11, 0.2);
    border-radius: 24px;
    overflow: hidden;
    backdrop-filter: blur(20px);
    box-shadow: 0 15px 40px rgba(0, 0, 0, 0.25), inset 0 0 20px rgba(245, 158, 11, 0.05);
  }
  .gift-glow {
    position: absolute;
    top: -50%;
    left: -20%;
    width: 60%;
    height: 200%;
    background: radial-gradient(circle, rgba(245, 158, 11, 0.1) 0%, transparent 70%);
    filter: blur(60px);
    pointer-events: none;
  }
  .gift-content { position: relative; z-index: 2; }
  .gift-tag {
    display: inline-block;
    padding: 4px 12px;
    background: linear-gradient(135deg, #F59E0B, #D97706);
    color: white;
    font-weight: 800;
    font-size: 0.6rem;
    border-radius: 100px;
    text-transform: uppercase;
    margin-bottom: 0.8rem;
    letter-spacing: 0.08em;
    box-shadow: 0 4px 12px rgba(217, 119, 6, 0.3);
  }
  .gift-main { display: flex; justify-content: space-between; align-items: center; gap: 1.5rem; }
  .gift-text h2 { font-size: 1.8rem; font-weight: 900; color: white; margin-bottom: 0.4rem; letter-spacing: -0.04em; }
  .gift-text p { font-size: 0.95rem; color: #94a3b8; max-width: 400px; line-height: 1.4; }
  .gift-visual { display: flex; align-items: center; gap: 2rem; }
  .gift-price-tag { display: flex; flex-direction: column; align-items: flex-end; }
  .gift-price-tag .val { font-size: 2.5rem; font-weight: 950; color: #22C55E; line-height: 1; filter: drop-shadow(0 0 10px rgba(34, 197, 94, 0.3)); }
  .gift-price-tag .sub { font-size: 1rem; color: #94a3b8; font-weight: 700; text-decoration: line-through; opacity: 0.4; }
  .btn-gift {
    background: #F59E0B;
    color: black;
    padding: 0.8rem 1.8rem;
    border-radius: 12px;
    font-weight: 900;
    font-size: 0.95rem;
    border: none;
    cursor: pointer;
    transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1);
    box-shadow: 0 5px 15px rgba(245, 158, 11, 0.2);
    animation: gift-pulse 2s infinite;
  }
  .btn-gift:hover { transform: translateY(-4px) translateZ(0); box-shadow: 0 10px 25px rgba(245, 158, 11, 0.4); background: #fbbf24; }
  
  @keyframes gift-pulse {
    0% { opacity: 0.9; box-shadow: 0 5px 15px rgba(245, 158, 11, 0.2); }
    50% { opacity: 1; box-shadow: 0 5px 30px rgba(245, 158, 11, 0.5); }
    100% { opacity: 0.9; box-shadow: 0 5px 15px rgba(245, 158, 11, 0.2); }
  }

  /* ── Searchable Dropdown ── */
  .search-results {
    position: absolute;
    top: calc(100% + 5px);
    left: 0;
    width: 100%;
    z-index: 100;
    max-height: 250px;
    overflow-y: auto;
    border: 1px solid rgba(255,255,255,0.1);
    box-shadow: 0 20px 40px rgba(0,0,0,0.4);
    background: rgba(10, 10, 15, 0.98) !important;
    backdrop-filter: blur(10px);
    border-radius: 12px;
  }
  .result-item {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    background: transparent;
    border: none;
    border-bottom: 1px solid rgba(255,255,255,0.05);
    color: white;
    cursor: pointer;
    text-align: left;
    transition: all 0.2s;
    transform: none !important;
  }
  .result-item:hover { 
    background: rgba(255, 255, 255, 0.08) !important; 
    border-left: 4px solid var(--red);
    padding-left: 12px;
  }
  .res-num { font-family: 'JetBrains Mono', monospace; font-weight: 700; color: #EF4444; }
  .res-name { font-size: 0.85rem; color: #94a3b8; }
  .selection-status { margin-top: 1rem; padding: 10px; background: rgba(34, 197, 94, 0.1); border-radius: 8px; color: #22C55E; font-size: 0.9rem; }

  .badge-plan-basic, .badge-plan-standard, .badge-plan-premium, .badge-plan-gold, .badge-plan-elite { 
    background: rgba(248, 113, 113, 0.1); 
    color: #fca5a5; 
    border: 1px solid rgba(248, 113, 113, 0.2);
    border-left: 3px solid #f87171;
  }

</style>