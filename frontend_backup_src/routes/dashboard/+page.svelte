<script>
  let profile = $state(null);
  let contracts = $state([]);
  let invoices = $state([]);

  async function load() {
    try {
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

<svelte:head><title>Dashboard — FMRZ</title></svelte:head>

<div class="container">
  <div class="page-header">
    <h1>My <span class="text-gradient">Dashboard</span></h1>
  </div>

  <div class="grid-3">
    <div class="stat-card animate-fade">
      <span class="stat-label">Active Contracts</span>
      <span class="stat-value">{contracts.filter(c => c.status === 'active').length}</span>
    </div>
    <div class="stat-card animate-fade" style="animation-delay: 0.1s">
      <span class="stat-label">Total Invoices</span>
      <span class="stat-value">{invoices.length}</span>
    </div>
    <div class="stat-card animate-fade" style="animation-delay: 0.2s">
      <span class="stat-label">Account Status</span>
      <div class="status-indicator {profile?.status?.toLowerCase() || 'active'}">
        <span class="status-dot"></span>
        <span class="status-text">{profile?.status || 'Active'}</span>
      </div>
    </div>
  </div>

  {#if profile}
    <div class="section animate-fade" style="animation-delay: 0.3s">
      <h2>Profile</h2>
      <div class="card profile-card">
        <div class="profile-header">
          <div class="profile-avatar">{profile.name.charAt(0).toUpperCase()}</div>
          <div class="profile-info">
            <span class="profile-name">{profile.name}</span>
            <span class="profile-id">Customer ID: #{profile.id}</span>
          </div>
        </div>
        <div class="profile-details">
          <div class="profile-row"><span class="label">Address</span><span>{profile.address || '—'}</span></div>
          <div class="profile-row"><span class="label">Email</span><span>{profile.email || '—'}</span></div>
        </div>
        <a href="/dashboard/profile" class="btn btn-secondary" style="width: fit-content; margin-top: 1rem;">Edit Profile</a>
      </div>
    </div>
  {/if}

  {#if contracts.length > 0}
    <div class="section animate-fade" style="animation-delay: 0.4s">
      <h2>My Contracts</h2>
      <div class="table-wrapper">
        <table>
          <thead><tr><th>MSISDN</th><th>Plan</th><th>Status</th><th>Credit</th></tr></thead>
          <tbody>
            {#each contracts as c}
              <tr>
                <td style="font-weight: 600;">{c.msisdn}</td>
                <td>{c.rateplanName || '—'}</td>
                <td>
                   <div class="flex items-center gap-2">
                     <span class="status-dot-sm {c.status}"></span>
                     <span class="badge badge-{c.status}">{c.status}</span>
                   </div>
                </td>
                <td style="font-weight: 700;">{c.availableCredit} EGP</td>
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
  .section { margin-top: 2.5rem; }
  .section h2 { font-size: 1.25rem; margin-bottom: 1.5rem; font-weight: 700; }
  
  /* Status Indicator */
  .status-indicator { display: flex; align-items: center; gap: 0.75rem; margin-top: 0.5rem; }
  .status-dot { width: 10px; height: 10px; border-radius: 50%; animation: pulse-glow 2s infinite; }
  .status-text { font-size: 1.5rem; font-weight: 800; text-transform: capitalize; }
  
  /* Status Colors */
  .status-indicator.active .status-dot { background: #22C55E; box-shadow: 0 0 12px #22C55E; }
  .status-indicator.active .status-text { color: #22C55E; }
  .status-indicator.on-hold .status-dot { background: var(--yellow); box-shadow: 0 0 12px var(--yellow); }
  .status-indicator.on-hold .status-text { color: var(--yellow); }
  .status-indicator.deactivated .status-dot { background: var(--text-muted); box-shadow: 0 0 12px var(--text-muted); }
  .status-indicator.deactivated .status-text { color: var(--text-muted); }

  .status-dot-sm { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
  .status-dot-sm.active { background: #22C55E; }
  .status-dot-sm.suspended { background: var(--yellow); }

  /* Profile Card */
  .profile-card { max-width: 500px; padding: 2rem; }
  .profile-header { display: flex; align-items: center; gap: 1.5rem; margin-bottom: 2rem; }
  .profile-avatar { width: 64px; height: 64px; background: var(--red); color: white; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 1.75rem; font-weight: 800; box-shadow: var(--shadow-red); }
  .profile-info { display: flex; flex-direction: column; }
  .profile-name { font-size: 1.25rem; font-weight: 700; display: block; }
  .profile-id { font-size: 0.8rem; color: var(--text-muted); }
  .profile-details { border-top: 1px solid var(--border); padding-top: 1rem; }
  .profile-row { display: flex; justify-content: space-between; padding: 0.75rem 0; font-size: 0.95rem; }
  .profile-row .label { color: var(--text-muted); }

  @keyframes pulse-glow {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.5; transform: scale(1.1); }
  }
</style>
