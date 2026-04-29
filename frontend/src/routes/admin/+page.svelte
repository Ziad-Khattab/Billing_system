<script>
  import { base } from '$app/paths';
  import { page } from '$app/stores';
  import { onMount, onDestroy } from 'svelte';
  import RatePlanManager from './components/RatePlanManager.svelte';
  import ServicePkgManager from './components/ServicePkgManager.svelte';

  let activeTab = $state('dashboard');

  let stats = $state({ customers: 0, contracts: 0, active: 0, suspended: 0, suspended_debt: 0, terminated: 0, cdrs: 0 });
  let systemStatus = $state('Online');
  let pollInterval;

  async function checkHealth() {
    try {
      const res = await fetch('/health');
      systemStatus = res.ok ? 'Online' : 'Offline';
    } catch (e) {
      systemStatus = 'Offline';
    }
  }

  async function fetchStats() {
    try {
      const res = await fetch('/api/admin/stats', { credentials: 'include' });
      if (res.ok) {
        const data = await res.json();
        stats.customers = data.customers || 0;
        stats.contracts = data.contracts || 0;
        stats.active = data.active_contracts || 0;
        stats.suspended = data.suspended_contracts || 0;
        stats.suspended_debt = data.suspended_debt_contracts || 0;
        stats.terminated = data.terminated_contracts || 0;
        stats.cdrs = data.cdrs || 0;
      }
    } catch {}
  }

  onMount(() => {
    checkHealth();
    fetchStats();
    pollInterval = setInterval(() => {
      checkHealth();
      fetchStats();
    }, 30000);
  });

  onDestroy(() => {
    clearInterval(pollInterval);
  });
</script>

<svelte:head><title>Admin Dashboard — FMRZ</title></svelte:head>

<div class="container">
  <div class="page-header">
    <h1>Admin <span class="text-gradient">Dashboard</span></h1>
    <div class="admin-tabs">
      <button class="admin-tab-btn" class:active={activeTab === 'dashboard'} onclick={() => activeTab = 'dashboard'}>Overview</button>
      <button class="admin-tab-btn" class:active={activeTab === 'rateplans'} onclick={() => activeTab = 'rateplans'}>Rate Plans</button>
      <button class="admin-tab-btn" class:active={activeTab === 'packages'} onclick={() => activeTab = 'packages'}>Service Catalog</button>
    </div>
  </div>

  {#if activeTab === 'dashboard'}
    <div class="animate-fade">
      <!-- System Status Bar -->
      <div class="system-status-bar animate-fade" class:status-offline={systemStatus === 'Offline'}>
        <div class="status-pill">
          <div class="status-pulse" class:pulse-offline={systemStatus === 'Offline'}></div>
          <span class="status-text" class:text-online={systemStatus === 'Online'} class:text-offline={systemStatus === 'Offline'}>
            System Gateway {systemStatus}
          </span>
        </div>
        <div class="system-time">{new Date().toLocaleTimeString()}</div>
      </div>

      <div class="stats-bento-grid stats-container">
        <!-- Hero Card: Contracts -->
        <div class="premium-card contract-gradient hero-card animate-fade">
          <div class="card-content-hero">
            <div class="hero-header">
              <div class="icon-circle">
                <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>
              </div>
              <div class="stat-main-hero">
                <span class="stat-value-large">{stats.contracts}</span>
                <span class="stat-label">Total Contracts</span>
              </div>
            </div>
            <div class="status-grid-hero">
              <div class="status-item-box status-active">
                <span class="val">{stats.active}</span>
                <span class="lbl">Active</span>
              </div>
              <div class="status-item-box status-onhold">
                <span class="val">{stats.suspended}</span>
                <span class="lbl">On Hold</span>
              </div>
              <div class="status-item-box status-suspended">
                <span class="val">{stats.suspended_debt}</span>
                <span class="lbl">Suspended (Debt)</span>
              </div>
              <div class="status-item-box status-terminated">
                <span class="val">{stats.terminated}</span>
                <span class="lbl">Deactivated</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Info Cards -->
        <div class="premium-card customer-gradient animate-fade" style="animation-delay: 0.1s">
          <div class="card-content-centered">
            <div class="icon-circle">
              <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
            </div>
            <div class="stat-info-centered">
              <span class="stat-value">{stats.customers}</span>
              <span class="stat-label">Total Customers</span>
            </div>
          </div>
        </div>

        <div class="premium-card cdr-gradient animate-fade" style="animation-delay: 0.2s">
          <div class="card-content-centered">
            <div class="icon-circle">
              <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
            </div>
            <div class="stat-info-centered">
              <span class="stat-value">{stats.cdrs || 0}</span>
              <span class="stat-label">Processed CDRs</span>
            </div>
          </div>
        </div>
      </div>

      <div class="quick-actions-section">
        <div class="section-header">
          <h2>Quick Management</h2>
          <p>Direct shortcuts to core system modules</p>
        </div>

        <div class="grid-admin">
          <a href="/admin/customers" class="action-card card">
            <div class="action-icon-box">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
            </div>
            <h3>Manage Customers</h3>
            <p>Full CRM control panel</p>
          </a>
          <a href="/admin/contracts" class="action-card card">
            <div class="action-icon-box">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>
            </div>
            <h3>Contracts</h3>
            <p>Service lifecycle management</p>
          </a>
          <a href="/admin/billing" class="action-card card">
            <div class="action-icon-box">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>
            </div>
            <h3>Billing Engine</h3>
            <p>Invoices & financial records</p>
          </a>
          <button onclick={() => activeTab = 'rateplans'} class="action-card card">
            <div class="action-icon-box icon-purple">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="3" y1="10" x2="21" y2="10"/><line x1="9" y1="22" x2="9" y2="10"/><line x1="8" y1="4" x2="8" y2="2"/></svg>
            </div>
            <h3>Rate Plans</h3>
            <p>Pricing & default bundles</p>
          </button>
          <button onclick={() => activeTab = 'packages'} class="action-card card">
            <div class="action-icon-box icon-green">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5"/><path d="M2 12l10 5 10-5"/></svg>
            </div>
            <h3>Service Catalog</h3>
            <p>Define voice/data/sms bundles</p>
          </button>
          <a href="/admin/cdr" class="action-card card">
            <div class="action-icon-box">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
            </div>
            <h3>Call Explorer</h3>
            <p>Advanced CDR analysis tool</p>
          </a>
        </div>
      </div>
    </div>
  {:else if activeTab === 'rateplans'}
    <div class="animate-fade">
      <RatePlanManager />
    </div>
  {:else if activeTab === 'packages'}
    <div class="animate-fade">
      <ServicePkgManager />
    </div>
  {/if}
</div>

<style>
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .stats-container { margin-bottom: 3.5rem; }

  .page-header { display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 2.5rem; }
  .admin-tabs { display: flex; gap: 0.5rem; background: rgba(255,255,255,0.03); padding: 5px; border-radius: 12px; border: 1px solid var(--border); }
  .admin-tab-btn { padding: 8px 16px; border: none; background: none; color: var(--text-muted); font-weight: 700; font-size: 0.85rem; border-radius: 8px; cursor: pointer; transition: all 0.2s; }
  .admin-tab-btn:hover { color: white; background: rgba(255,255,255,0.05); }
  .admin-tab-btn.active { color: white; background: var(--red); }
  
  .premium-card {
    padding: 2rem;
    border-radius: var(--radius-lg);
    border: 1px solid var(--border);
    transition: all 0.3s ease;
    overflow: hidden;
    position: relative;
    height: 100%;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .premium-card:hover { 
    transform: translateY(-5px); 
    background: rgba(22, 22, 34, 0.85); 
    border-color: rgba(224, 8, 0, 0.3); 
    box-shadow: 0 15px 35px rgba(0,0,0,0.4);
  }
  
  .system-status-bar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid var(--border);
    padding: 0.75rem 1.75rem;
    border-radius: 50px;
    margin-bottom: 2.5rem;
  }
  .status-pill { display: flex; align-items: center; gap: 0.75rem; }
  .system-time { font-family: monospace; color: var(--text-muted); font-size: 0.9rem; }

  .stats-bento-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 1.5rem;
    margin-bottom: 3.5rem;
  }
  .hero-card { grid-column: span 2; }

  .card-content-hero { display: flex; flex-direction: column; gap: 2.5rem; padding: 0.5rem; }
  .hero-header { display: flex; align-items: center; gap: 1.75rem; }
  .stat-value-large { font-size: 2.75rem; font-weight: 900; letter-spacing: -0.04em; line-height: 1; }
  
  .status-grid-hero { 
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 1rem;
    width: 100%;
  }
  .status-item-box {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 1rem;
    border-radius: 16px;
    border: 1px solid rgba(255, 255, 255, 0.05);
    transition: all 0.3s ease;
  }
  .status-item-box .val { font-size: 1.5rem; font-weight: 800; display: block; line-height: 1; margin-bottom: 0.25rem; }
  .status-item-box .lbl { font-size: 0.7rem; color: rgba(255, 255, 255, 0.5); text-transform: uppercase; font-weight: 700; letter-spacing: 0.05em; }

  .status-active { background: rgba(34, 197, 94, 0.1); border-color: rgba(34, 197, 94, 0.2); }
  .status-active .val { color: #22C55E; }
  
  .status-onhold { background: rgba(245, 158, 11, 0.1); border-color: rgba(245, 158, 11, 0.2); }
  .status-onhold .val { color: #F59E0B; }
  
  .status-suspended { background: rgba(239, 68, 68, 0.1); border-color: rgba(239, 68, 68, 0.2); }
  .status-suspended .val { color: #EF4444; }
  
  .status-terminated { background: rgba(168, 85, 247, 0.1); border-color: rgba(168, 85, 247, 0.2); }
  .status-terminated .val { color: #A855F7; }

  .status-item-box:hover { transform: scale(1.05); background: rgba(255, 255, 255, 0.05); }

  .card-content-centered { 
    display: flex; 
    flex-direction: column;
    align-items: center; 
    text-align: center;
    gap: 1rem; 
    width: 100%;
  }
  .icon-circle { width: 56px; height: 56px; border-radius: 16px; display: flex; align-items: center; justify-content: center; background: rgba(255, 255, 255, 0.05); }
  
  .stat-info-centered { display: flex; flex-direction: column; align-items: center; width: 100%; }
  .stat-value { font-size: 2.25rem; font-weight: 800; letter-spacing: -0.02em; line-height: 1.1; }
  .stat-label { font-size: 0.8rem; color: var(--text-muted); font-weight: 600; text-transform: uppercase; margin-top: 0.25rem; letter-spacing: 0.05em; }

  /* Gradients */
  .customer-gradient .icon-circle { color: #3B82F6; background: rgba(59, 130, 246, 0.15); }
  .contract-gradient .icon-circle { color: #F59E0B; background: rgba(245, 158, 11, 0.15); }
  .cdr-gradient .icon-circle { color: #EF4444; background: rgba(239, 68, 68, 0.15); }
  
  .text-active { color: #22C55E; }
  .text-suspended { color: #EF4444; }
  .text-debt { color: #F59E0B; }
  .text-terminated { color: #A855F7; }
  .status-gradient .icon-circle { background: rgba(34, 197, 94, 0.15); }

  .text-online { color: #22C55E; text-shadow: 0 0 10px rgba(34, 197, 94, 0.3); }
  .text-offline { color: #EF4444; text-shadow: 0 0 10px rgba(239, 68, 68, 0.3); }
  
  .status-pulse { width: 12px; height: 12px; background: #22C55E; border-radius: 50%; box-shadow: 0 0 15px #22C55E; animation: pulse-glow 2s infinite; }
  .pulse-offline { background: #EF4444; box-shadow: 0 0 15px #EF4444; }
  
  .status-offline { border-color: rgba(239, 68, 68, 0.3) !important; background: rgba(239, 68, 68, 0.05) !important; }

  .grid-admin {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1.5rem;
  }
  @media (max-width: 1024px) { .grid-admin { grid-template-columns: repeat(2, 1fr); } }
  @media (max-width: 600px) { .grid-admin { grid-template-columns: 1fr; } }

  .icon-purple { color: #A855F7 !important; background: rgba(168, 85, 247, 0.1) !important; }
  .icon-green { color: #22C55E !important; background: rgba(34, 197, 94, 0.1) !important; }

  .quick-actions-section { border-top: 1px solid var(--border); padding-top: 2.5rem; }
  .section-header { margin-bottom: 2rem; }
  .section-header h2 { font-size: 1.5rem; font-weight: 800; }
  .action-card { 
    display: flex; flex-direction: column; align-items: center; text-align: center; 
    padding: 2.5rem 1.5rem;
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    text-decoration: none; color: inherit; height: 100%;
  }
  .action-card:hover { 
    transform: translateY(-5px);
    border-color: var(--red);
  }
  .action-icon-box { 
    width: 64px; height: 64px; background: rgba(224, 8, 0, 0.1); 
    border-radius: 18px; display: flex; align-items: center; justify-content: center; 
    margin-bottom: 1.5rem; color: var(--red);
  }
  .action-card h3 { font-size: 1.25rem; font-weight: 700; margin-bottom: 0.5rem; color: white; }
  .action-card p { font-size: 0.85rem; color: var(--text-muted); line-height: 1.4; }

  @keyframes pulse-glow { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.5; transform: scale(1.25); } }
</style>
