<script>
  let contractId = $state('');
  let bills = $state([]);
  let missingBills = $state([]);
  let stats = $state({ revenue: 0, pending_bills: 0, contracts: 0 });
  let loading = $state(true);
  let showAudit = $state(false);
  let processingBills = $state(false);

  async function loadData() {
    loading = true;
    try {
      const [billsRes, statsRes, missingRes] = await Promise.all([
        fetch(contractId ? `/api/admin/bills?contract_id=${contractId}` : '/api/admin/bills', { credentials: 'include' }),
        fetch('/api/admin/stats', { credentials: 'include' }),
        fetch('/api/admin/bills/missing', { credentials: 'include' })
      ]);
      
      if (billsRes.ok) bills = await billsRes.json();
      if (statsRes.ok) stats = await statsRes.json();
      if (missingRes.ok) missingBills = await missingRes.json();
    } catch (e) {
    } finally {
      loading = false;
    }
  }

  async function forceRunBilling() {
    if (!confirm("This will generate bills for all active contracts for the current month. Proceed?")) return;
    processingBills = true;
    try {
      const res = await fetch('/api/admin/bills/generate', { method: 'POST', credentials: 'include' });
      if (res.ok) {
        alert("Billing cycle completed successfully!");
        loadData();
      } else {
        alert("Failed to run billing cycle.");
      }
    } catch (e) {
      alert("Network error.");
    } finally {
      processingBills = false;
    }
  }

  $effect(() => {
    loadData();
  });
</script>

<svelte:head><title>Billing — FMRZ Admin</title></svelte:head>

<div class="container">
  <div class="page-header" style="display:flex; justify-content:space-between; align-items:center;">
    <div>
      <h1>Billing & <span class="text-gradient">Invoices</span></h1>
      <p class="text-muted">Monitor network revenue and audit historical subscriber statements</p>
    </div>
    <button class="btn btn-primary" onclick={forceRunBilling} disabled={processingBills}>
      {#if processingBills}
        <div class="mini-spinner"></div> Processing...
      {:else}
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right:8px"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
        Run Billing Cycle Now
      {/if}
    </button>
  </div>

  <!-- Summary Stats Cards -->
  <div class="stats-grid">
    <div class="card stat-card info-card card-static">
      <div class="stat-icon">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>
      </div>
      <div class="stat-info">
        <span class="stat-label">Total Revenue</span>
        <span class="stat-value">{stats.revenue || 0} EGP</span>
      </div>
    </div>
    <div class="card stat-card info-card card-static">
      <div class="stat-icon">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>
      </div>
      <div class="stat-info">
        <span class="stat-label">Pending Collection</span>
        <span class="stat-value">{stats.pending_bills || 0}</span>
      </div>
    </div>
    <div class="card stat-card info-card card-static" onclick={() => showAudit = !showAudit} style="cursor:pointer">
      <div class="stat-icon">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={missingBills.length > 0 ? "var(--red)" : "var(--text-muted)"} stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
      </div>
      <div class="stat-info">
        <span class="stat-label">Missing Statements</span>
        <span class="stat-value">{missingBills.length}</span>
      </div>
      <div class="card-hint">{showAudit ? 'Hide Audit' : 'Show Audit'}</div>
    </div>
  </div>

  {#if showAudit && missingBills.length > 0}
    <div class="audit-section animate-fade card" style="border-color: var(--red); margin-bottom: 2rem; background: rgba(224, 8, 0, 0.05)">
      <h2 style="color: var(--red); margin-bottom: 1rem;">⚠️ Billing Audit: Missing Statements</h2>
      <p class="text-muted" style="margin-bottom: 1.5rem;">The following active contracts have no bill generated for the current month.</p>
      <div class="table-wrapper">
        <table>
          <thead>
            <tr><th>Contract ID</th><th>MSISDN</th><th>Customer</th><th>Last Bill Date</th><th>Action</th></tr>
          </thead>
          <tbody>
            {#each missingBills as m}
              <tr>
                <td><span class="id-badge">#{m.id}</span></td>
                <td><span class="phone-num">{m.msisdn}</span></td>
                <td>{m.customer_name}</td>
                <td>{m.last_bill_date || 'Never'}</td>
                <td><button class="btn btn-secondary btn-sm" onclick={forceRunBilling}>Generate</button></td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>
  {/if}
  
  <div class="search-bar animate-fade">
    <div style="display:flex;gap:1rem;margin-bottom:2rem">
      <div class="input-wrapper" style="flex:1; max-width: 300px;">
        <input class="input" placeholder="Filter by Contract ID..." bind:value={contractId} type="number" onkeydown={e => e.key === 'Enter' && loadData()} />
      </div>
      <button class="btn btn-primary" onclick={loadData}>Search Records</button>
      {#if contractId}
        <button class="btn btn-secondary" onclick={() => { contractId = ''; loadData(); }}>Clear Filter</button>
      {/if}
    </div>
  </div>
  
  {#if loading}
    <div class="loading-state">
      <div class="spinner"></div>
      <p>Synchronizing billing records...</p>
    </div>
  {:else if bills.length > 0}
  <div class="table-wrapper animate-fade">
    <table>
      <thead>
        <tr>
          <th>Bill ID</th><th>Customer</th><th>Period</th><th>Usage (V/D/S)</th><th>Total</th><th>Status</th>
        </tr>
      </thead>
      <tbody>
        {#each bills as b}
        <tr>
          <td><span class="id-badge">#{b.id}</span></td>
          <td>
            <div class="customer-cell">
              <span class="name">{b.customer_name || 'System User'}</span>
              <span class="msisdn text-muted">{b.msisdn || '--'}</span>
            </div>
          </td>
          <td class="text-muted">{b.billing_period_start}</td>
          <td>
            <div class="usage-pills">
              <span class="pill voice" title="Voice">{b.voice_usage}m</span>
              <span class="pill data" title="Data">{b.data_usage}MB</span>
              <span class="pill sms" title="SMS">{b.sms_usage}</span>
            </div>
          </td>
          <td><span class="amount-num bold">{b.total_amount} EGP</span></td>
          <td>
            <span class="badge status-{b.status || 'issued'}">
              {b.status || 'issued'}
            </span>
          </td>
        </tr>
        {/each}
      </tbody>
    </table>
  </div>
  {:else}
  <div class="empty-state card">
    <div style="margin-bottom:1.5rem">
      <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--text-muted)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M9 21V9"/></svg>
    </div>
    <h3>No Billing Records Found</h3>
    <p class="text-muted">There are currently no bills matching your search criteria.</p>
  </div>
  {/if}
</div>

<style>
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1.5rem;
    margin-bottom: 2.5rem;
  }

  .info-card {
    display: flex;
    align-items: center;
    gap: 1.5rem;
    padding: 1.5rem;
    border: 1px solid var(--border);
    position: relative;
    overflow: hidden;
  }

  .card-hint {
    position: absolute;
    bottom: 8px;
    right: 12px;
    font-size: 0.7rem;
    color: var(--text-muted);
    text-transform: uppercase;
    opacity: 0;
    transition: opacity 0.3s;
  }
  .info-card:hover .card-hint { opacity: 1; }

  .stat-icon {
    font-size: 2.5rem;
    background: var(--bg-soft);
    width: 60px;
    height: 60px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--radius-md);
  }

  .stat-info {
    display: flex;
    flex-direction: column;
  }

  .stat-label {
    font-size: 0.85rem;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .stat-value {
    font-size: 1.5rem;
    font-weight: 700;
    color: white;
  }

  .customer-cell { display: flex; flex-direction: column; }
  .customer-cell .name { font-weight: 600; font-size: 0.95rem; }
  .customer-cell .msisdn { font-size: 0.8rem; }

  .mini-spinner { width: 14px; height: 14px; border: 2px solid rgba(255, 255, 255, 0.3); border-top-color: white; border-radius: 50%; animation: spin 0.8s linear infinite; display: inline-block; margin-right: 8px; }
  @keyframes spin { to { transform: rotate(360deg); } }

  .usage-pills { display: flex; gap: 4px; }
  .pill {
    font-size: 0.75rem;
    padding: 2px 8px;
    border-radius: 10px;
    font-weight: 600;
    background: var(--bg-soft);
    color: var(--text-secondary);
  }
  .pill.voice { border-left: 3px solid #3B82F6; }
  .pill.data { border-left: 3px solid #A855F7; }
  .pill.sms { border-left: 3px solid #F59E0B; }

  .amount-num.bold { font-size: 1rem; color: white; }

  .badge.status-paid { background: rgba(34, 197, 94, 0.1); color: #22c55e; border: 1px solid rgba(34, 197, 94, 0.2); }
  .badge.status-issued { background: rgba(59, 130, 246, 0.1); color: #3b82f6; border: 1px solid rgba(59, 130, 246, 0.2); }
  .badge.status-draft { background: rgba(255, 255, 255, 0.05); color: var(--text-muted); border: 1px solid var(--border); }

  .loading-state { text-align: center; padding: 5rem; }
  .empty-state { text-align: center; padding: 4rem; }
  
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .btn-sm { padding: 4px 12px; font-size: 0.8rem; }
</style>
