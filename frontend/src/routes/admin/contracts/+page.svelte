<script>
  import { showToast } from '$lib/toast.svelte.js';
  import Modal from '$lib/components/Modal.svelte';
  let contracts = $state([]);
  let customers = $state([]);
  let plans = $state([]);
  let loading = $state(false);
  let showModal = $state(false);
  let customerSearch = $state('');
  let showDropdown = $state(false);

  // Form State
  let newMsisdn = $state('');
  let selectedCustomer = $state(null); // {id, name, msisdn}
  let selectedPlan = $state('');
  let creditLimit = $state(1000);

  async function loadData() {
    try {
      const [cRes, uRes, pRes] = await Promise.all([
        fetch('/api/admin/contracts', { credentials: 'include' }),
        fetch('/api/admin/customers', { credentials: 'include' }),
        fetch('/api/admin/rateplans', { credentials: 'include' })
      ]);
      if (cRes.ok) contracts = await cRes.json();
      if (uRes.ok) customers = await uRes.json();
      if (pRes.ok) plans = await pRes.json();
    } catch {}
  }

  $effect(() => { loadData(); });

  let filteredCustomers = $derived(
    customerSearch 
      ? customers.filter(u => u.name.toLowerCase().includes(customerSearch.toLowerCase()) || u.msisdn.includes(customerSearch))
      : customers.slice(0, 10)
  );

  function selectCustomer(u) {
    selectedCustomer = u;
    customerSearch = u.name;
    showDropdown = false;
  }

  async function provisionLine(e) {
    e.preventDefault();
    if (!selectedCustomer) { showToast("Please select a customer", 'error'); return; }
    loading = true;
    try {
      const res = await fetch('/api/admin/contracts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          msisdn: newMsisdn,
          userId: selectedCustomer.id,
          planId: selectedPlan,
          creditLimit: creditLimit
        })
      });
      if (res.ok) {
        showToast('Line provisioned successfully!');
        showModal = false;
        newMsisdn = '';
        selectedCustomer = null;
        customerSearch = '';
        loadData();
      } else {
        const err = await res.json();
        showToast(err.error || 'Provisioning failed', 'error');
      }
    } finally {
      loading = false;
    }
  }
</script>

<svelte:head><title>Contracts — FMRZ Admin</title></svelte:head>

<div class="container">
  <div class="page-header" style="display:flex; justify-content:space-between; align-items:center;">
    <div>
      <h1>Service <span class="text-gradient">Contracts</span></h1>
      <p class="text-muted">Manage and provision phone lines across the subscriber base</p>
    </div>
    <button class="btn btn-primary" onclick={() => showModal = true}>
      + Provision New Line
    </button>
  </div>

  <div class="table-wrapper animate-fade">
    <table>
      <thead>
        <tr><th>ID</th><th>MSISDN</th><th>Customer</th><th>Plan</th><th>Status</th><th>Credit</th></tr>
      </thead>
      <tbody>
        {#each contracts as c}
          <tr>
            <td><span class="id-badge">#{c.id}</span></td>
            <td><span class="phone-num">{c.msisdn}</span></td>
            <td style="font-weight:600">{c.customerName||'—'}</td>
            <td><span class="badge badge-customer">{c.rateplanName||'—'}</span></td>
            <td><span class="badge status-{c.status}">{c.status}</span></td>
            <td>
              <span class="amount-num" style={c.availableCredit < 0 ? 'color: #ef4444' : ''}>
                {c.availableCredit} EGP
              </span>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>

  <Modal bind:show={showModal} title="Provision New Line" type="admin">
    <form onsubmit={provisionLine}>
      <div class="form-group" style="position:relative">
        <label class="label">Search Customer (Type to search)</label>
        <input 
          class="input" 
          placeholder="Start typing name or MSISDN..." 
          bind:value={customerSearch} 
          onfocus={() => showDropdown = true}
          oninput={() => showDropdown = true}
        />
        {#if showDropdown && filteredCustomers.length > 0}
          <div class="search-dropdown card animate-fade">
            {#each filteredCustomers as u}
              <button type="button" class="dropdown-item" onclick={() => selectCustomer(u)}>
                <span class="name">{u.name}</span>
                <span class="msisdn">{u.msisdn}</span>
              </button>
            {/each}
          </div>
        {/if}
      </div>

      <div class="grid-2">
        <div class="form-group">
          <label class="label">New MSISDN</label>
          <input class="input" placeholder="010XXXXXXXX" bind:value={newMsisdn} required />
        </div>
        <div class="form-group">
          <label class="label">Initial Credit Limit</label>
          <input class="input" type="number" bind:value={creditLimit} required />
        </div>
      </div>

      <div class="form-group">
        <label class="label">Select Rate Plan</label>
        <select class="input" bind:value={selectedPlan} required>
          <option value="">-- Choose a Plan --</option>
          {#each plans as p}
            <option value={p.id}>{p.name} ({p.price} EGP/mo)</option>
          {/each}
        </select>
      </div>

      <div style="display:flex;gap:1rem;justify-content:flex-end;margin-top:2rem">
        <button type="button" class="btn btn-secondary" onclick={() => showModal = false}>Cancel</button>
        <button type="submit" class="btn btn-primary" disabled={loading}>
          {loading ? 'Processing...' : 'Assign Line'}
        </button>
      </div>
    </form>
  </Modal>

<style>
  
  .search-dropdown {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    z-index: 1100;
    margin-top: 4px;
    max-height: 200px;
    overflow-y: auto;
    background: #11111a;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    box-shadow: 0 10px 30px rgba(0,0,0,0.5);
  }

  .dropdown-item {
    width: 100%;
    text-align: left;
    padding: 0.75rem 1rem;
    background: transparent;
    border: none;
    border-bottom: 1px solid rgba(255,255,255,0.05);
    cursor: pointer;
    display: flex;
    justify-content: space-between;
    align-items: center;
    transition: background 0.2s;
  }

  .dropdown-item:hover { background: rgba(224, 8, 0, 0.1); }
  .dropdown-item .name { color: white; font-weight: 600; }
  .dropdown-item .msisdn { font-size: 0.8rem; color: var(--text-muted); }

  .badge.status-active { background: rgba(34, 197, 94, 0.1); color: #22c55e; border: 1px solid rgba(34, 197, 94, 0.2); }
  .badge.status-suspended { background: rgba(224, 8, 0, 0.1); color: var(--red-light); border: 1px solid rgba(224, 8, 0, 0.2); }
</style>
