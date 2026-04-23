<script>
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
      const res = await fetch('/api/admin/customers', { credentials: 'include' });
      if (res.ok) {
        const customers = await res.json();
        stats.customers = customers.length;
      }
      const cRes = await fetch('/api/admin/contracts', { credentials: 'include' });
      if (cRes.ok) {
        const contracts = await cRes.json();
        stats.contracts = contracts.length;
      }
      const bRes = await fetch('/api/admin/bills', { credentials: 'include' });
      if (bRes.ok) {
        const bills = await bRes.json();
        stats.invoices = bills.length;
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

  <div class="grid-4">
    <div class="stat-card animate-fade">
      <span class="stat-label">Customers</span>
      <span class="stat-value">{stats.customers}</span>
    </div>
    <div class="stat-card animate-fade" style="animation-delay: 0.1s">
      <span class="stat-label">Contracts</span>
      <span class="stat-value">{stats.contracts}</span>
    </div>
    <div class="stat-card animate-fade" style="animation-delay: 0.2s">
      <span class="stat-label">Invoices</span>
      <span class="stat-value">{stats.invoices}</span>
    </div>
    <div class="stat-card animate-fade" style="animation-delay: 0.3s">
      <span class="stat-label">System Status</span>
      <div class="status-indicator">
        <span class="status-dot"></span>
        <span class="status-text">Online</span>
      </div>
    </div>
  </div>

  <div class="quick-actions">
    <h2>Quick Actions</h2>
    <div class="grid-3">
      <a href="/admin/customers" class="action-card card">
        <div class="action-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
        </div>
        <h3>Manage Customers</h3>
        <p>Add, search, and edit customer profiles</p>
      </a>
      <a href="/admin/contracts" class="action-card card">
        <div class="action-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>
        </div>
        <h3>Contracts</h3>
        <p>View and manage service contracts</p>
      </a>
      <a href="/admin/billing" class="action-card card">
        <div class="action-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>
        </div>
        <h3>Billing & Invoices</h3>
        <p>Generate bills and download invoices</p>
      </a>
    </div>
  </div>
</div>

<style>
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .quick-actions { margin-top: 3rem; }
  .quick-actions h2 { font-size: 1.25rem; margin-bottom: 1.5rem; }
  
  /* Status Indicator */
  .status-indicator { display: flex; align-items: center; gap: 0.75rem; margin-top: 0.5rem; }
  .status-dot { width: 10px; height: 10px; background: #22C55E; border-radius: 50%; box-shadow: 0 0 12px #22C55E; animation: pulse-glow 2s infinite; }
  .status-text { font-size: 1.5rem; font-weight: 800; color: #22C55E; }
  
  /* Action Cards */
  .action-card { text-align: center; padding: 2.5rem 2rem; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); }
  .action-card:hover { transform: translateY(-5px); border-color: var(--red); box-shadow: 0 10px 30px rgba(224, 8, 0, 0.15); }
  .action-icon { color: var(--red); display: inline-flex; margin-bottom: 1.5rem; padding: 1rem; background: rgba(224, 8, 0, 0.1); border-radius: 12px; }
  .action-card h3 { font-size: 1.1rem; font-weight: 700; margin-bottom: 0.5rem; }
  .action-card p { font-size: 0.85rem; color: var(--text-muted); line-height: 1.5; }

  @keyframes pulse-glow {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.5; transform: scale(1.1); }
  }
</style>
