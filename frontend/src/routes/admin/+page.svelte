<script>
  import { base } from '$app/paths';
  import { page } from '$app/stores';

  let stats = $state({ customers: 0, contracts: 0, invoices: 0 });

  async function load() {
    // 1. Security Check: Only admins allowed
    const authRes = await fetch('/api/auth/me', { credentials: 'include' });
    if (!authRes.ok) {
      window.location.href = '/login';
      return;
    }
    const user = await authRes.json();
    if (user.role !== 'admin') {
      window.location.href = '/dashboard';
      return;
    }

    try {
      const res = await fetch('/api/admin/stats', { credentials: 'include' });
      if (res.ok) {
        const data = await res.json();
        stats.customers = data.customers;
        stats.contracts = data.contracts;
        stats.cdrs = data.cdrs;
      }
    } catch {}
  }

  $effect(() => { load(); });
</script>

<svelte:head><title>Admin Dashboard — FMRZ</title></svelte:head>

<div class="container">
  <div class="page-header">
    <h1>Admin <span class="text-gradient">Dashboard</span></h1>
  </div>

  <div class="grid-4 stats-container">
    <div class="premium-card customer-gradient animate-fade">
      <div class="card-content">
        <div class="icon-circle">
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
        </div>
        <div class="stat-info">
          <span class="stat-value">{stats.customers}</span>
          <span class="stat-label">Total Customers</span>
        </div>
      </div>
    </div>

    <div class="premium-card contract-gradient animate-fade" style="animation-delay: 0.1s">
      <div class="card-content">
        <div class="icon-circle">
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>
        </div>
        <div class="stat-info">
          <span class="stat-value">{stats.contracts}</span>
          <span class="stat-label">Active Contracts</span>
        </div>
      </div>
    </div>

    <div class="premium-card cdr-gradient animate-fade" style="animation-delay: 0.2s">
      <div class="card-content">
        <div class="icon-circle">
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
        </div>
        <div class="stat-info">
          <span class="stat-value">{stats.cdrs || 0}</span>
          <span class="stat-label">Processed CDRs</span>
        </div>
      </div>
    </div>

    <div class="premium-card status-gradient animate-fade" style="animation-delay: 0.3s">
      <div class="card-content">
        <div class="icon-circle">
          <div class="status-pulse"></div>
        </div>
        <div class="stat-info">
          <span class="stat-value text-online">Online</span>
          <span class="stat-label">System Gateway</span>
        </div>
      </div>
    </div>
  </div>

  <div class="quick-actions-section">
    <div class="section-header">
      <h2>Quick Management</h2>
      <p>Direct shortcuts to core system modules</p>
    </div>

    <div class="grid-4">
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

<style>
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .stats-container { margin-bottom: 3.5rem; }
  
  .premium-card {
    padding: 1.5rem;
    border-radius: 20px;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.05);
    transition: all 0.3s ease;
    overflow: hidden;
    position: relative;
  }
  .premium-card:hover { transform: translateY(-5px); background: rgba(255, 255, 255, 0.06); border-color: rgba(255, 255, 255, 0.1); }
  
  .card-content { display: flex; align-items: center; gap: 1.25rem; }
  .icon-circle { width: 50px; height: 50px; border-radius: 14px; display: flex; align-items: center; justify-content: center; background: rgba(255, 255, 255, 0.05); }
  
  .stat-info { display: flex; flex-direction: column; }
  .stat-value { font-size: 1.75rem; font-weight: 800; letter-spacing: -0.02em; line-height: 1.1; }
  .stat-label { font-size: 0.75rem; color: var(--text-muted); font-weight: 600; text-transform: uppercase; margin-top: 0.25rem; }

  /* Gradients */
  .customer-gradient .icon-circle { color: #3B82F6; background: rgba(59, 130, 246, 0.1); }
  .contract-gradient .icon-circle { color: #F59E0B; background: rgba(245, 158, 11, 0.1); }
  .cdr-gradient .icon-circle { color: var(--red); background: rgba(224, 8, 0, 0.1); }
  .status-gradient .icon-circle { background: rgba(34, 197, 94, 0.1); }

  .text-online { color: #22C55E; text-shadow: 0 0 10px rgba(34, 197, 94, 0.3); }
  .status-pulse { width: 12px; height: 12px; background: #22C55E; border-radius: 50%; box-shadow: 0 0 15px #22C55E; animation: pulse-glow 2s infinite; }

  .quick-actions-section { border-top: 1px solid var(--border); padding-top: 2.5rem; }
  .section-header { margin-bottom: 2rem; }
  .section-header h2 { font-size: 1.5rem; font-weight: 800; }
  .actions-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1.5rem; }
  .action-card { 
    display: flex; flex-direction: column; align-items: center; text-align: center; 
    padding: 2rem 1.5rem; border-radius: 20px; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    border: 1px solid transparent; text-decoration: none; color: inherit; height: 100%;
  }
  .action-card:hover { 
    background: rgba(255, 255, 255, 0.08); 
    transform: translateY(-5px);
    box-shadow: 0 0 0 1px var(--red), 0 10px 30px rgba(0, 0, 0, 0.3);
  }
  .action-icon-box { 
    width: 100%; aspect-ratio: 16/9; background: rgba(224, 8, 0, 0.1); 
    border-radius: 15px; display: flex; align-items: center; justify-content: center; 
    margin-bottom: 1.5rem; color: var(--red);
  }
  .action-card h3 { font-size: 1.1rem; font-weight: 700; margin-bottom: 0.5rem; color: white; }
  .action-card p { font-size: 0.85rem; color: var(--text-muted); line-height: 1.4; }

  @keyframes pulse-glow { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.4; transform: scale(1.2); } }
</style>
