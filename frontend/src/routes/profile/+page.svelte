<script>
  import { base } from '$app/paths';
  let profile = $state(null);
  let contracts = $state([]);
  let invoices = $state([]);

  async function load() {
    // 1. Security Check
    try {
      const authRes = await fetch('/api/auth/me', { credentials: 'include' });
      if (!authRes.ok) {
        window.location.href = '/login';
        return;
      }
      const user = await authRes.json();
      if (user.role !== 'customer') {
        window.location.href = '/admin';
        return;
      }

      const [pRes, cRes, iRes] = await Promise.all([
        fetch('/api/customer/profile', { credentials: 'include' }),
        fetch('/api/customer/contracts', { credentials: 'include' }),
        fetch('/api/customer/invoices', { credentials: 'include' })
      ]);
      if (pRes.ok) profile = await pRes.json();
      if (cRes.ok) contracts = await cRes.json();
      if (iRes.ok) invoices = await iRes.json();
    } catch {}
  }

  $effect(() => { load(); });
</script>

<svelte:head><title>Profile — FMRZ</title></svelte:head>

<div class="container">
  <div class="page-header">
    <h1>My <span class="text-gradient">Profile</span></h1>
  </div>

  <div class="grid-3 stats-container">
    <div class="premium-card contract-gradient animate-fade">
      <div class="card-content">
        <div class="icon-circle">
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>
        </div>
        <div class="stat-info">
          <span class="stat-value">{contracts.filter(c => c.status === 'active').length}</span>
          <span class="stat-label">Active Contracts</span>
        </div>
      </div>
    </div>

    <div class="premium-card invoice-gradient animate-fade" style="animation-delay: 0.1s">
      <div class="card-content">
        <div class="icon-circle">
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>
        </div>
        <div class="stat-info">
          <span class="stat-value">{invoices.length}</span>
          <span class="stat-label">Total Invoices</span>
        </div>
      </div>
    </div>

    <div class="premium-card status-gradient animate-fade" style="animation-delay: 0.2s">
      <div class="card-content">
        <div class="icon-circle">
          <div class="status-pulse"></div>
        </div>
        <div class="stat-info">
          <span class="stat-value text-online">{profile?.status || 'Active'}</span>
          <span class="stat-label">Account Status</span>
        </div>
      </div>
    </div>
  </div>

  {#if profile}
    <div class="profile-section animate-fade" style="animation-delay: 0.3s">
      <div class="section-header">
        <h2>Account Info</h2>
        <p>Personal details and contact information</p>
      </div>

      <div class="card profile-card">
        <div class="profile-header">
          <div class="avatar-large">{profile.name.charAt(0).toUpperCase()}</div>
          <div class="profile-title">
            <h3>{profile.name}</h3>
            <span class="text-muted">Customer ID: #{profile.id}</span>
          </div>
        </div>
        
        <div class="profile-details">
          <div class="detail-row">
            <span class="detail-label">Address</span>
            <span class="detail-value">{profile.address || 'Not provided'}</span>
          </div>
          <div class="detail-row">
            <span class="detail-label">Email</span>
            <span class="detail-value">{profile.email || '—'}</span>
          </div>
        </div>
        
        <div class="profile-actions">
          <a href="/profile/edit" class="btn btn-secondary">Edit Profile</a>
        </div>
      </div>
    </div>
  {/if}

  {#if contracts.length > 0}
    <div class="section animate-fade" style="animation-delay: 0.4s">
      <div class="section-header">
        <h2>My Contracts</h2>
        <p>Current active and pending service plans</p>
      </div>
      <div class="table-wrapper">
        <table>
          <thead><tr><th>MSISDN</th><th>Plan</th><th>Status</th><th>Credit</th></tr></thead>
          <tbody>
            {#each contracts as c}
              <tr>
                <td><span class="phone-num">{c.msisdn}</span></td>
                <td style="font-weight:600">{c.rateplanName || '—'}</td>
                <td>
                   <div class="flex items-center gap-2">
                     <span class="badge badge-{c.status}">{c.status}</span>
                   </div>
                </td>
                <td><span class="amount-num">{c.availableCredit} EGP</span></td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>
  {/if}

  {#if invoices.length > 0}
    <div class="section animate-fade" style="animation-delay: 0.5s; margin-top: 3rem;">
      <div class="section-header">
        <h2>My Invoices</h2>
        <p>Historical billing records and financial statements</p>
      </div>
      <div class="table-wrapper">
        <table>
          <thead><tr><th>ID</th><th>Date</th><th>Amount</th><th>Status</th></tr></thead>
          <tbody>
            {#each invoices as inv}
              <tr>
                <td><span class="id-badge">#{inv.id}</span></td>
                <td class="text-muted">{inv.generationDate}</td>
                <td><span class="amount-num">{inv.totalAmount} EGP</span></td>
                <td><span class="badge badge-active">{inv.status === 'paid' ? 'Paid' : 'Pending'}</span></td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>
  {/if}
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
  .contract-gradient .icon-circle { color: #F59E0B; background: rgba(245, 158, 11, 0.1); }
  .invoice-gradient .icon-circle { color: #22C55E; background: rgba(34, 197, 94, 0.1); }
  .status-gradient .icon-circle { background: rgba(34, 197, 94, 0.1); }

  .text-online { color: #22C55E; text-shadow: 0 0 10px rgba(34, 197, 94, 0.3); }
  .status-pulse { width: 12px; height: 12px; background: #22C55E; border-radius: 50%; box-shadow: 0 0 15px #22C55E; animation: pulse-glow 2s infinite; }

  .profile-section { margin-top: 2.5rem; }
  .section-header { margin-bottom: 1.5rem; }
  .section-header h2 { font-size: 1.5rem; font-weight: 800; }
  .section-header p { font-size: 0.9rem; color: var(--text-muted); }

  /* Profile Card */
  .profile-card { max-width: 500px; padding: 2.5rem; border-radius: 24px; }
  .profile-header { display: flex; align-items: center; gap: 1.5rem; margin-bottom: 2rem; }
  .avatar-large { width: 64px; height: 64px; background: var(--red); color: white; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 1.75rem; font-weight: 800; box-shadow: var(--shadow-red); }
  .profile-title h3 { font-size: 1.25rem; font-weight: 700; }
  
  .profile-details { border-top: 1px solid var(--border); padding-top: 1.5rem; display: flex; flex-direction: column; gap: 1rem; }
  .detail-row { display: flex; justify-content: space-between; font-size: 0.95rem; }
  .detail-label { color: var(--text-muted); }
  .detail-value { font-weight: 500; }
  .profile-actions { margin-top: 2rem; }

  .status-dot-sm { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
  .status-dot-sm.active { background: #22C55E; }
  .status-dot-sm.suspended { background: var(--yellow); }

  @keyframes pulse-glow { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.4; transform: scale(1.2); } }
</style>
