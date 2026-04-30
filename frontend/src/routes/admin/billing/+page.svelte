<script>
  import { showToast } from '$lib/toast.svelte.js';
  import ConfirmModal from '$lib/components/ConfirmModal.svelte';
  let contractId = $state('');
  // Billing History State
  let bills = $state([]);
  let billsTotal = $state(0);
  let billsSearch = $state('');
  let billsPage = $state(0);
  let billsLimit = $state(25);
  let billsJumpPage = $state(1);
  const billsTotalPages = $derived(Math.ceil(billsTotal / billsLimit));
  
  // Missing Statements (Audit) State
  let missingBills = $state([]);
  let missingTotal = $state(0);
  let systemMissingTotal = $state(0); // UNFILTERED total for status badges
  let missingSearch = $state('');
  let missingPage = $state(0);
  let missingLimit = $state(25);
  let missingJumpPage = $state(1);
  const missingTotalPages = $derived(Math.ceil(missingTotal / missingLimit));

  let stats = $state({ revenue: 0, pending_bills: 0, contracts: 0 });
  let loading = $state(true);
  let loadingAudit = $state(false);
  let showAudit = $state(false);
  
  // Rejected CDR (Audit) State
  let rejectedCdrs = $state([]);
  let rejectedTotal = $state(0);
  let showRejected = $state(false);
  let loadingRejected = $state(false);

  let processingBills = $state(false);
  
  // Selection State
  let selectedIds = $state(new Set());
  let isGlobalSelection = $state(false);
  let selectedAuditIds = $state(new Set());
  let isAuditGlobalSelection = $state(false);

  // Confirm Modals State
  let showRunConfirm = $state(false);
  let showPayConfirm = $state(false);
  let showBulkConfirm = $state(false);
  let targetBillId = $state(null);

  async function loadData() {
    loading = true;
    try {
      const statsRes = await fetch('/api/admin/stats', { credentials: 'include' });
      if (statsRes.ok) stats = await statsRes.json();
      
      // Fetch system-wide missing count first (without filter) for status color
      const auditRes = await fetch('/api/admin/bills/missing?limit=1', { credentials: 'include' });
      if (auditRes.ok) {
        const res = await auditRes.json();
        systemMissingTotal = res.total || 0;
      }

      await Promise.all([
        loadBills(),
        loadAudit(),
        loadRejected()
      ]);
    } catch (e) {
    } finally {
      loading = false;
    }
  }

  async function loadBills() {
    try {
      const offset = billsPage * billsLimit;
      const url = contractId 
        ? `/api/admin/bills?contract_id=${contractId}` 
        : `/api/admin/bills?search=${billsSearch}&limit=${billsLimit}&offset=${offset}`;
      
      const res = await fetch(url, { credentials: 'include' });
      if (res.ok) {
        const result = await res.json();
        if (contractId) {
            bills = result;
            billsTotal = result.length;
        } else {
            bills = result.data || [];
            billsTotal = result.total || 0;
            billsJumpPage = billsPage + 1;
        }
      }
    } catch (e) {}
  }

  function handleBillsSearch() {
    clearTimeout(window.billsSearchTimeout);
    window.billsSearchTimeout = setTimeout(() => {
      billsPage = 0;
      selectedIds.clear();
      isGlobalSelection = false;
      selectedIds = new Set();
      loadBills();
    }, 300);
  }

  function nextBillsPage() { if ((billsPage + 1) * billsLimit < billsTotal) { billsPage++; loadBills(); } }
  function prevBillsPage() { if (billsPage > 0) { billsPage--; loadBills(); } }
  function gotoBillsPage() {
    const target = Math.max(1, Math.min(billsJumpPage, billsTotalPages));
    billsPage = target - 1;
    loadBills();
  }
  function handleBillsLimitChange() {
    billsPage = 0;
    loadBills();
  }

  async function loadAudit() {
    loadingAudit = true;
    try {
      const offset = missingPage * missingLimit;
      const res = await fetch(`/api/admin/bills/missing?search=${missingSearch}&limit=${missingLimit}&offset=${offset}`, { credentials: 'include' });
      if (res.ok) {
        const result = await res.json();
        missingBills = result.data || [];
        missingTotal = result.total || 0;
        missingJumpPage = missingPage + 1;
      }
    } finally {
      loadingAudit = false;
    }
  }

  async function loadRejected() {
    loadingRejected = true;
    try {
      const res = await fetch('/api/admin/audit', { credentials: 'include' });
      if (res.ok) {
        rejectedCdrs = await res.json();
        rejectedTotal = rejectedCdrs.length;
      }
    } finally {
      loadingRejected = false;
    }
  }

  function handleAuditSearch() {
    clearTimeout(window.auditSearchTimeout);
    window.auditSearchTimeout = setTimeout(() => {
      missingPage = 0;
      selectedAuditIds.clear();
      isAuditGlobalSelection = false;
      selectedAuditIds = new Set();
      loadAudit();
    }, 300);
  }

  function nextAuditPage() { if ((missingPage + 1) * missingLimit < missingTotal) { missingPage++; loadAudit(); } }
  function prevAuditPage() { if (missingPage > 0) { missingPage--; loadAudit(); } }
  function gotoAuditPage() {
    const target = Math.max(1, Math.min(missingJumpPage, missingTotalPages));
    missingPage = target - 1;
    loadAudit();
  }
  function handleAuditLimitChange() {
    missingPage = 0;
    loadAudit();
  }

  async function forceRunBilling() {
    showRunConfirm = true;
  }

  async function executeRunBilling() {
    showRunConfirm = false;
    processingBills = true;
    try {
      const res = await fetch('/api/admin/bills/generate', { method: 'POST', credentials: 'include' });
      if (res.ok) {
        showToast("Billing cycle completed successfully!");
        loadData();
      } else {
        showToast("Failed to run billing cycle.", 'error');
      }
    } catch (e) {
      showToast("Network error.", 'error');
    } finally {
      processingBills = false;
    }
  }

  async function generateSingleBill(cid) {
    processingBills = true;
    try {
      const res = await fetch(`/api/admin/bills/generate?contractId=${cid}`, { method: 'POST', credentials: 'include' });
      if (res.ok) {
        showToast(`Statement generated for Contract #${cid}`);
        loadData();
      } else {
        showToast("Generation failed.", 'error');
      }
    } catch (e) {
      showToast("Network error.", 'error');
    } finally {
      processingBills = false;
    }
  }

  async function payBill(billId) {
    targetBillId = billId;
    showPayConfirm = true;
  }

  async function executePayBill() {
    if (!targetBillId) return;
    const billId = targetBillId;
    showPayConfirm = false;
    try {
      const res = await fetch(`/api/admin/bills/pay?billId=${billId}`, { method: 'POST', credentials: 'include' });
      if (res.ok) {
        showToast(`Bill #${billId} marked as paid.`);
        selectedIds.delete(billId);
        selectedIds = new Set(selectedIds);
        loadData();
      } else {
        showToast("Payment update failed.", 'error');
      }
    } catch (e) {
      showToast("Network error.", 'error');
    }
  }

  async function bulkPay() {
    if (selectedIds.size === 0 && !isGlobalSelection) return;
    showBulkConfirm = true;
  }

  async function executeBulkPay() {
    showBulkConfirm = false;
    try {
      let url = '/api/admin/bills/pay-bulk';
      if (isGlobalSelection) {
        url += `?global=true&search=${encodeURIComponent(billsSearch)}`;
      } else {
        url += `?ids=${Array.from(selectedIds).join(',')}`;
      }
      
      const res = await fetch(url, { method: 'POST', credentials: 'include' });
      if (res.ok) {
        showToast(isGlobalSelection ? `All matching bills marked as paid.` : `${selectedIds.size} bills marked as paid.`);
        selectedIds.clear();
        isGlobalSelection = false;
        selectedIds = new Set(selectedIds);
        loadData();
      } else {
        showToast("Bulk payment failed.", 'error');
      }
    } catch (e) {
      showToast("Network error.", 'error');
    }
  }

  function formatData(mb) {
    if (!mb || mb === 0) return '0MB';
    if (mb >= 1024) return (mb / 1024).toFixed(1) + 'GB';
    return mb + 'MB';
  }

  function toggleSelect(id) {
    if (selectedIds.has(id)) selectedIds.delete(id);
    else selectedIds.add(id);
    isGlobalSelection = false;
    selectedIds = new Set(selectedIds);
  }

  function toggleAll() {
    const selectable = bills.filter(b => b.status !== 'paid');
    if (selectedIds.size === selectable.length && selectedIds.size > 0) {
      selectedIds.clear();
      isGlobalSelection = false;
    } else {
      selectable.forEach(b => selectedIds.add(b.id));
    }
    selectedIds = new Set(selectedIds);
  }

  function toggleAuditSelect(id) {
    if (selectedAuditIds.has(id)) selectedAuditIds.delete(id);
    else selectedAuditIds.add(id);
    isAuditGlobalSelection = false;
    selectedAuditIds = new Set(selectedAuditIds);
  }

  function toggleAllAudit() {
    if (selectedAuditIds.size === missingBills.length && missingBills.length > 0) {
      selectedAuditIds.clear();
      isAuditGlobalSelection = false;
    } else {
      missingBills.forEach(m => selectedAuditIds.add(m.contract_id));
    }
    selectedAuditIds = new Set(selectedAuditIds);
  }

  async function bulkGenerateAudit() {
    if (selectedAuditIds.size === 0 && !isAuditGlobalSelection) return;
    processingBills = true;
    try {
      if (isAuditGlobalSelection) {
        // Global Audit Generation
        const res = await fetch(`/api/admin/bills/generate-bulk?global=truFMRZsearch=${encodeURIComponent(missingSearch)}`, { 
            method: 'POST', 
            credentials: 'include' 
        });
        if (res.ok) showToast("Global billing generation triggered.");
      } else {
        const ids = Array.from(selectedAuditIds);
        let successCount = 0;
        for (const cid of ids) {
          const res = await fetch(`/api/admin/bills/generate?contractId=${cid}`, { method: 'POST', credentials: 'include' });
          if (res.ok) successCount++;
        }
        showToast(`Successfully generated ${successCount} statements.`);
      }
      selectedAuditIds.clear();
      isAuditGlobalSelection = false;
      selectedAuditIds = new Set(selectedAuditIds);
      loadData();
    } catch (e) {
      showToast("Network error during bulk generation.", 'error');
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

  <ConfirmModal 
    bind:show={showRunConfirm} 
    title="Run Billing Cycle" 
    message="This will generate bills for all active contracts for the current month. This process may take a few seconds as it triggers the automated PDF generator."
    onconfirm={executeRunBilling}
    loading={processingBills}
    type="admin"
  />

  <ConfirmModal 
    bind:show={showPayConfirm} 
    title="Confirm Payment" 
    message="Are you sure you want to mark Bill #{targetBillId} as paid? This will update the collection status in the financial records."
    onconfirm={executePayBill}
    type="admin"
  />

  <ConfirmModal 
    bind:show={showBulkConfirm} 
    title="Bulk Payment" 
    message="Are you sure you want to mark {isGlobalSelection ? billsTotal : selectedIds.size} selected bills as paid? This action cannot be undone."
    onconfirm={executeBulkPay}
    type="admin"
  />

  <!-- Summary Stats Cards -->
  <div class="stats-grid">
    <div class="card stat-card info-card">
      <div class="stat-icon">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>
      </div>
      <div class="stat-info">
        <span class="stat-label">Total Revenue</span>
        <span class="stat-value">{stats.revenue || 0} EGP</span>
      </div>
    </div>
    <div class="card stat-card info-card">
      <div class="stat-icon">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>
      </div>
      <div class="stat-info">
        <span class="stat-label">Pending Collection</span>
        <span class="stat-value">{stats.pending_bills || 0}</span>
      </div>
    </div>
    <div class="card stat-card info-card" onclick={() => showAudit = !showAudit} style="cursor:pointer; border-color: {systemMissingTotal > 0 ? 'rgba(239, 68, 68, 0.3)' : 'rgba(34, 197, 94, 0.3)'}">
      <div class="stat-icon-plain">
        <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" 
             stroke={systemMissingTotal > 0 ? "#FF0000" : "#22C55E"} stroke-width="3" stroke-linecap="round" stroke-linejoin="round"
             class={systemMissingTotal > 0 ? 'icon-pulse-red' : ''}>
          {#if systemMissingTotal > 0}
            <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
          {:else}
            <polyline points="20 6 9 17 4 12"/>
          {/if}
        </svg>
      </div>
      <div class="stat-info">
        <span class="stat-label">Missing Statements</span>
        <span class="stat-value">{systemMissingTotal}</span>
      </div>
      <div class="card-hint">{showAudit ? 'Hide Audit' : 'Show Audit'}</div>
    </div>
    <div class="card stat-card info-card" onclick={() => showRejected = !showRejected} style="cursor:pointer; border-color: {rejectedTotal > 0 ? 'rgba(249, 115, 22, 0.3)' : 'rgba(255, 255, 255, 0.1)'}">
      <div class="stat-icon-plain">
        <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" 
             stroke={rejectedTotal > 0 ? "#F97316" : "#888"} stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
        </svg>
      </div>
      <div class="stat-info">
        <span class="stat-label">Blocked Usage</span>
        <span class="stat-value">{rejectedTotal}</span>
      </div>
      <div class="card-hint">{showRejected ? 'Hide Log' : 'Show Rejections'}</div>
    </div>
  </div>

  {#if showAudit}
    <div class="audit-section animate-fade" style="--audit-accent: {systemMissingTotal > 0 ? '#EF4444' : '#22C55E'}">
      <div class="audit-header" style="margin-top: 1rem; border: none; flex-wrap: wrap;">
        <div style="display:flex; align-items:center; gap:1.5rem; flex:1">
          <div class="audit-badge" 
               style="background: rgba({systemMissingTotal > 0 ? '239, 68, 68' : '34, 197, 94'}, 0.1); 
                      color: var(--audit-accent); 
                      border-color: var(--audit-accent);
                      border-radius: {systemMissingTotal > 0 ? '8px' : '50px'};">
            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
              {#if systemMissingTotal > 0}
                <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z" stroke="#EF4444"/><line x1="12" y1="9" x2="12" y2="13" stroke="#EF4444"/><line x1="12" y1="17" x2="12.01" y2="17" stroke="#EF4444"/>
              {:else}
                <circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>
              {/if}
            </svg>
            {systemMissingTotal > 0 ? 'Critical Audit' : 'Audit Clear'}
          </div>
          <div class="audit-text">
            <h2>{systemMissingTotal > 0 ? 'Pending Billing Statements' : 'Billing Synchronized'}</h2>
            <p>{systemMissingTotal > 0 ? 'These active contracts have no generated bills for the current cycle.' : 'Excellent! All matching contracts have been billed for the current period.'}</p>
          </div>
        </div>
        
        <div class="search-box-mini">
           <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
           <input type="text" placeholder="Search MSISDN or Customer..." bind:value={missingSearch} oninput={handleAuditSearch} />
        </div>

        {#if selectedAuditIds.size > 0 || isAuditGlobalSelection}
          <button class="btn btn-primary btn-sm animate-fade" onclick={bulkGenerateAudit} style="background: var(--audit-accent); border:none; margin-left: 1rem; color: #000; font-weight: 800;">
            Generate {isAuditGlobalSelection ? missingTotal : selectedAuditIds.size} Selected
          </button>
        {/if}
        {#if selectedAuditIds.size === missingBills.length && missingTotal > missingBills.length}
          <div class="selection-banner audit-banner animate-fade">
            {#if isAuditGlobalSelection}
              <span>✨ <b>All {missingTotal}</b> missing statements matching search are selected.</span>
              <button class="btn-link" onclick={() => { isAuditGlobalSelection = false; selectedAuditIds.clear(); selectedAuditIds = new Set(); }}>Clear selection</button>
            {:else}
              <span>All {selectedAuditIds.size} items on this page are selected.</span>
              <button class="btn-link" onclick={() => isAuditGlobalSelection = true}>Select all <b>{missingTotal}</b> items matching search</button>
            {/if}
          </div>
        {/if}
      </div>
      
      <div class="table-wrapper audit-table-wrapper" 
           style="border-color: #F59E0B; margin-bottom: 3rem; background: rgba({systemMissingTotal > 0 ? '245, 158, 11' : '34, 197, 94'}, 0.05); position: relative; min-height: 400px;">
        
        {#if loadingAudit}
          <div class="loading-overlay animate-fade">
            <div class="mini-spinner" style="width:32px; height:32px; border-width:3px; border-top-color:#F59E0B"></div>
            <p style="color: #F59E0B; font-weight: 600;">Updating audit list...</p>
          </div>
        {/if}

        {#if !loadingAudit && missingBills.length === 0}
          <div class="empty-state animate-fade" style="padding: 4rem 2rem; color: #22C55E; background: rgba(34, 197, 94, 0.05); border-radius: 40px; border: 1px solid rgba(34, 197, 94, 0.1); margin: 2rem;">
            <div style="margin-bottom: 1.5rem;">
              <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="10" stroke-opacity="0.3"/>
                <path d="m9 12 2 2 4-4"/>
              </svg>
            </div>
            <h3 style="font-size: 1.75rem; font-weight: 800; margin-bottom: 0.5rem;">Excellent!</h3>
            <p style="font-size: 1.1rem; opacity: 0.8;">All matching contracts have been successfully billed.</p>
          </div>
        {:else}
          <table class:dimmed={loadingAudit}>
            <thead>
              <tr>
                <th style="width: 40px;">
                  <input type="checkbox" checked={selectedAuditIds.size === missingBills.length && missingBills.length > 0} onchange={toggleAllAudit} />
                </th>
                <th>Contract ID</th><th>Customer / MSISDN</th><th>Last Known Bill</th><th>Action Required</th>
              </tr>
            </thead>
            <tbody>
              {#each missingBills as m}
                <tr class:row-selected={selectedAuditIds.has(m.contract_id)}>
                  <td>
                    <input type="checkbox" checked={selectedAuditIds.has(m.contract_id)} onchange={() => toggleAuditSelect(m.contract_id)} />
                  </td>
                  <td><span class="id-badge">#{m.contract_id}</span></td>
                  <td>
                    <div class="customer-cell">
                      <span class="name" style="color: white;">{m.customer_name || 'System User'}</span>
                      <span class="msisdn text-muted">{m.msisdn}</span>
                    </div>
                  </td>
                  <td>
                    <span class="text-muted" style="font-size: 0.9rem;">
                      {m.last_bill_date ? `Last bill: ${m.last_bill_date}` : '⚠️ No history found'}
                    </span>
                  </td>
                  <td>
                    <button class="btn btn-secondary btn-sm" 
                            style="border-color: var(--red); color: var(--red-light);" 
                            onclick={() => generateSingleBill(m.contract_id)}
                            disabled={processingBills}>
                      {processingBills ? '...' : 'Generate Statement'}
                    </button>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>

          <div class="pagination audit-pagination">
            <div class="pagination-controls">
              <button class="btn-page" onclick={prevAuditPage} disabled={missingPage === 0}>Prev</button>
              <div class="page-jump">
                <input type="number" bind:value={missingJumpPage} min="1" max={missingTotalPages} class="input-jump" />
                <span>of {missingTotalPages}</span>
                <button class="btn-go" onclick={gotoAuditPage}>Go</button>
              </div>
              <button class="btn-page" onclick={nextAuditPage} disabled={(missingPage + 1) * missingLimit >= missingTotal}>Next</button>
            </div>
            <div class="pagination-settings">
              <select bind:value={missingLimit} onchange={handleAuditLimitChange} class="select-limit">
                <option value="25">25 / page</option>
                <option value="50">50 / page</option>
                <option value="100">100 / page</option>
              </select>
              <span class="total-info">{missingTotal} missing</span>
            </div>
          </div>
        {/if}
      </div>
    </div>
  {/if}
  
  {#if showRejected}
    <div class="audit-section animate-fade" style="margin-top: 1rem; border-color: #F97316;">
      <div class="audit-header" style="border:none; padding-bottom: 1rem;">
        <div style="display:flex; align-items:center; gap:1.5rem; flex:1">
          <div class="audit-badge" style="background: rgba(249, 115, 22, 0.1); color: #F97316; border-color: #F97316; border-radius: 8px;">
            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
            Blocked Usage Log
          </div>
          <div class="audit-text">
            <h2 style="color: white; margin: 0;">Access Denied Events</h2>
            <p style="margin: 0; font-size: 0.9rem; color: #888;">Real-time audit of usage records rejected by the rating engine (e.g. Suspended Contracts).</p>
          </div>
        </div>
        <button class="btn btn-ghost btn-sm" onclick={loadRejected} style="color: #F97316; font-weight: 700;">Refresh Log</button>
      </div>

      <div class="table-wrapper audit-table-wrapper" style="background: rgba(249, 115, 22, 0.02); min-height: auto; border-color: rgba(249, 115, 22, 0.2); margin-bottom: 2rem;">
        {#if loadingRejected}
          <div style="padding: 3rem; text-align: center;">
            <div class="mini-spinner" style="border-top-color: #F97316; width: 30px; height: 30px;"></div>
            <p style="margin-top: 1rem; color: #F97316;">Loading audit records...</p>
          </div>
        {:else if rejectedCdrs.length === 0}
          <div style="padding: 3rem; text-align: center; color: #888;">
             <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" style="opacity:0.3; margin-bottom:1rem;"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>
             <p>No blocked usage recorded in the current audit window.</p>
          </div>
        {:else}
          <table>
            <thead>
              <tr>
                <th>Time</th><th>Source MSISDN</th><th>Target</th><th>Service</th><th>Reason</th>
              </tr>
            </thead>
            <tbody>
              {#each rejectedCdrs as r}
                <tr class="hover-row">
                  <td class="text-muted" style="font-size: 0.85rem;">{r.rejected_at}</td>
                  <td><span class="id-badge" style="background: rgba(249, 115, 22, 0.1); color: white; border: 1px solid rgba(249, 115, 22, 0.2);">#{r.dial_a}</span></td>
                  <td>{r.dial_b}</td>
                  <td><span class="pill {r.service_name?.toLowerCase().includes('voice') ? 'voice' : r.service_name?.toLowerCase().includes('data') ? 'data' : 'sms'}">{r.service_name || 'Unknown'}</span></td>
                  <td>
                    {#if r.rejection_reason === 'NO_CONTRACT_FOUND'}
                      <span class="badge" style="font-size: 0.75rem; background: rgba(156, 163, 175, 0.15); border: 1px solid rgba(156, 163, 175, 0.3); color: #9CA3AF;">
                        {r.rejection_reason.replace(/_/g, ' ')}
                      </span>
                    {:else if r.rejection_reason === 'CONTRACT_ADMIN_HOLD'}
                      <span class="badge" style="font-size: 0.75rem; background: rgba(245, 158, 11, 0.15); border: 1px solid rgba(245, 158, 11, 0.3); color: #F59E0B;">
                        {r.rejection_reason.replace(/_/g, ' ')}
                      </span>
                    {:else if r.rejection_reason === 'CONTRACT_DEBT_HOLD'}
                      <span class="badge" style="font-size: 0.75rem; background: rgba(239, 68, 68, 0.15); border: 1px solid rgba(239, 68, 68, 0.3); color: #EF4444;">
                        {r.rejection_reason.replace(/_/g, ' ')}
                      </span>
                    {:else}
                      <span class="badge" style="font-size: 0.75rem; background: rgba(153, 27, 27, 0.2); border: 1px solid rgba(153, 27, 27, 0.4); color: #FCA5A5;">
                        {r.rejection_reason.replace(/_/g, ' ')}
                      </span>
                    {/if}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        {/if}
      </div>
    </div>
  {/if}
  
  <div class="search-bar animate-fade" style="margin-top: 1rem;">
    <div style="display:flex;gap:1rem;margin-bottom:1.5rem; align-items: center;">
      <div class="search-box-mini" style="flex:1; max-width: 400px;">
         <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
         <input type="text" placeholder="Search invoices by customer, MSISDN or status..." bind:value={billsSearch} oninput={handleBillsSearch} style="width: 100%; padding-left: 36px;" />
      </div>
      {#if billsSearch}
        <button class="btn btn-ghost" onclick={() => { billsSearch = ''; loadBills(); }} style="color: var(--red); font-weight: 700;">Clear</button>
      {/if}
      {#if selectedIds.size > 0 || isGlobalSelection}
        <button class="btn btn-primary animate-fade" onclick={bulkPay} style="background: #22C55E; border:none; color: #000; font-weight: 800; margin-left: auto;">
          Mark {isGlobalSelection ? billsTotal : selectedIds.size} Selected as Paid
        </button>
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
    {#if selectedIds.size === bills.filter(b => b.status !== 'paid').length && billsTotal > bills.length}
      <div class="selection-banner animate-fade">
        {#if isGlobalSelection}
          <span>✨ <b>All {billsTotal}</b> bills matching search are selected.</span>
          <button class="btn-link" onclick={() => { isGlobalSelection = false; selectedIds.clear(); selectedIds = new Set(); }}>Clear selection</button>
        {:else}
          <span>All {selectedIds.size} items on this page are selected.</span>
          <button class="btn-link" onclick={() => isGlobalSelection = true}>Select all <b>{billsTotal}</b> bills matching search</button>
        {/if}
      </div>
    {/if}
    <table>
      <!-- ... existing table structure ... -->
      <thead>
        <tr>
          <th style="width: 40px;">
            <input type="checkbox" 
                   checked={selectedIds.size === bills.filter(b => b.status !== 'paid').length && bills.length > 0} 
                   onchange={toggleAll} />
          </th>
          <th>Bill ID</th><th>Customer</th><th>Period</th><th>Usage (V/D/S)</th><th>Total</th><th>Status</th><th>Actions</th>
        </tr>
      </thead>
      <tbody>
        {#each bills as b}
        <tr class:row-selected={selectedIds.has(b.id)}>
          <td>
            {#if b.status !== 'paid'}
              <input type="checkbox" checked={selectedIds.has(b.id)} onchange={() => toggleSelect(b.id)} />
            {:else}
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#22C55E" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
            {/if}
          </td>
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
              <span class="pill data" title="Data">{formatData(b.data_usage)}</span>
              <span class="pill sms" title="SMS">{b.sms_usage}</span>
            </div>
          </td>
          <td><span class="amount-num bold">{b.total_amount} EGP</span></td>
          <td>
            <span class="badge status-{b.status || 'issued'}">
              {b.status || 'issued'}
            </span>
          </td>
          <td>
            {#if b.status !== 'paid'}
              <button class="btn btn-secondary btn-sm" onclick={() => payBill(b.id)}>
                Mark Paid
              </button>
            {/if}
          </td>
        </tr>
        {/each}
      </tbody>
    </table>

    <div class="pagination">
      <div class="pagination-controls">
        <button class="btn-page" onclick={prevBillsPage} disabled={billsPage === 0}>Prev</button>
        <div class="page-jump">
          <input type="number" bind:value={billsJumpPage} min="1" max={billsTotalPages} class="input-jump" />
          <span>of {billsTotalPages}</span>
          <button class="btn-go" onclick={gotoBillsPage}>Go</button>
        </div>
        <button class="btn-page" onclick={nextBillsPage} disabled={(billsPage + 1) * billsLimit >= billsTotal}>Next</button>
      </div>
      <div class="pagination-settings">
        <select bind:value={billsLimit} onchange={handleBillsLimitChange} class="select-limit">
          <option value="25">25 / page</option>
          <option value="50">50 / page</option>
          <option value="100">100 / page</option>
        </select>
        <span class="total-info">{billsTotal} total bills</span>
      </div>
    </div>
  </div>
  {:else}
  <div class="empty-state animate-fade" style="padding: 5rem 2rem; background: rgba(255, 255, 255, 0.02); border: 1px dashed var(--border); border-radius: 32px; text-align: center; margin-top: 2rem;">
    <div style="margin-bottom:1.5rem; opacity: 0.5;">
      <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/><path d="m13.5 8.5-5 5"/><path d="m8.5 8.5 5 5"/>
      </svg>
    </div>
    <h3 style="font-size: 1.5rem; font-weight: 700; color: white;">No Billing Records Found</h3>
    <p class="text-muted" style="max-width: 400px; margin: 0.5rem auto;">There are currently no bills matching your search criteria or the system hasn't generated any for this period yet.</p>
    <button class="btn btn-secondary" onclick={() => { billsSearch = ''; loadBills(); }} style="margin-top: 1.5rem;">Reset Filter</button>
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
  .stat-icon-plain {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
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

  /* ── Audit Refinement ── */
  .search-box-mini { position: relative; display: flex; align-items: center; }
  .search-box-mini svg { position: absolute; left: 10px; color: var(--text-muted); }
  .search-box-mini input { padding: 6px 12px 6px 32px; background: rgba(255,255,255,0.05); border: 1px solid var(--border); border-radius: 8px; color: white; width: 250px; font-size: 0.85rem; }
  .search-box-mini input:focus { border-color: var(--red); outline: none; }

  .audit-pagination { border: none !important; padding: 1rem !important; background: rgba(224, 8, 0, 0.02) !important; flex-direction: row !important; justify-content: space-between; align-items: center !important; }
  .audit-pagination .pagination-controls { gap: 1rem !important; }

  .pagination { display: flex; flex-direction: column; align-items: center; gap: 1rem; padding: 1.5rem; border-top: 1px solid var(--border); background: rgba(255, 255, 255, 0.02); }
  .pagination-controls { display: flex; align-items: center; gap: 1.5rem; }
  .pagination-settings { display: flex; align-items: center; gap: 1rem; font-size: 0.85rem; color: var(--text-muted); }
  .page-jump { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: var(--text-muted); font-size: 0.9rem; }
  .input-jump { width: 45px; padding: 0.2rem 0.4rem; background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border); border-radius: 6px; color: white; text-align: center; font-size: 0.85rem; }
  .btn-go { background: var(--red); color: white; border: none; padding: 0.2rem 0.6rem; border-radius: 6px; font-weight: 600; cursor: pointer; transition: 0.2s; font-size: 0.85rem; }
  .btn-go:hover { background: var(--red-light); }
  .select-limit { background: rgba(255, 255, 255, 0.05); color: white; border: 1px solid var(--border); border-radius: 6px; padding: 0.2rem 0.4rem; outline: none; font-size: 0.85rem; }
  .select-limit:focus { border-color: var(--red); }
  .btn-page { background: rgba(255, 255, 255, 0.05); color: white; border: 1px solid var(--border); padding: 0.4rem 0.8rem; border-radius: 8px; font-weight: 600; cursor: pointer; transition: all 0.2s; font-size: 0.85rem; }
  .status-active, .status-paid { background: rgba(34, 197, 94, 0.1); color: #22C55E; border: 1px solid rgba(34, 197, 94, 0.2); font-weight: 700; text-transform: capitalize; }
  .status-suspended, .status-overdue, .status-unpaid { background: rgba(239, 68, 68, 0.1); color: #EF4444; border: 1px solid rgba(239, 68, 68, 0.2); font-weight: 700; text-transform: capitalize; }
  .status-issued, .status-pending { background: rgba(245, 158, 11, 0.1); color: #F59E0B; border: 1px solid rgba(245, 158, 11, 0.2); font-weight: 700; text-transform: capitalize; }

  /* Loading Stability */
  .loading-overlay {
    position: absolute;
    top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(10, 10, 15, 0.6);
    backdrop-filter: blur(2px);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    z-index: 10;
    gap: 1rem;
    border-radius: inherit;
  }
  .dimmed { opacity: 0.3; pointer-events: none; }

  /* Icon Glow & Pulse */
  .icon-pulse-red {
    animation: pulse-red-glow 2s infinite;
    filter: drop-shadow(0 0 2px rgba(239, 68, 68, 0.5));
  }

  @keyframes pulse-red-glow {
    0% { stroke: #FF0000; filter: drop-shadow(0 0 3px rgba(255, 0, 0, 0.6)); }
    50% { stroke: #FF3131; filter: drop-shadow(0 0 12px rgba(255, 0, 0, 0.9)); }
    100% { stroke: #FF0000; filter: drop-shadow(0 0 3px rgba(255, 0, 0, 0.6)); }
  }

  /* Audit Section Styles */
  .audit-section {
    background: rgba(239, 68, 68, 0.03);
    border: 1px solid rgba(239, 68, 68, 0.1);
    border-radius: 24px;
    padding: 2rem;
    margin-bottom: 2rem;
    position: relative;
    box-shadow: 0 10px 30px rgba(0,0,0,0.2);
  }
  .audit-header {
    display: flex;
    align-items: flex-start;
    gap: 1.5rem;
    margin-bottom: 2rem;
  }
  .audit-badge {
    padding: 6px 14px;
    font-size: 0.75rem;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    border-radius: 10px;
    border: 1px solid currentColor;
    display: flex;
    align-items: center;
    gap: 8px;
    white-space: nowrap;
  }
  .audit-text h2 { font-size: 1.4rem; font-weight: 800; color: white; margin-bottom: 0.25rem; }
  .audit-text p { font-size: 0.9rem; color: var(--text-muted); line-height: 1.5; }

  .selection-banner {
    background: #22C55E;
    color: #000;
    padding: 8px 16px;
    text-align: center;
    font-size: 0.9rem;
    font-weight: 600;
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 1rem;
  }
  .selection-banner.audit-banner {
    background: #F59E0B;
    margin: 0 1rem;
    border-radius: 8px;
    width: auto;
  }
  .btn-link {
    background: none;
    border: none;
    color: #000;
    text-decoration: underline;
    font-weight: 800;
    cursor: pointer;
    padding: 0;
  }
</style>
