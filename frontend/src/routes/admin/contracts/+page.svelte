<script>
  import { showToast } from '$lib/toast.svelte.js';
  import { authState } from '$lib/auth.svelte.js';
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
   let availableMsisdns = $state([]);
   let msisdnSearch = $state('');
   let showMsisdnDropdown = $state(false);
   let msisdnResults = $state([]);   // dropdown results (from client filter or server search)
   let msisdnSearchTimer;
   let selectedCustomer = $state(null); // {id, name, msisdn}
   let selectedPlan = $state('');
   let creditLimit = $state(1000);

  // New Customer Fields
  let isNewCustomer = $state(false);
  let newCustName = $state('');
  let newCustEmail = $state('');
  let newCustAddress = $state('');
  let newCustBirthdate = $state('');

  async function loadData() {
    try {
      const [cRes, uRes, pRes, mRes] = await Promise.all([
        fetch('/api/admin/contracts', { credentials: 'include' }),
        fetch('/api/admin/customers', { credentials: 'include' }),
        fetch('/api/admin/rateplans', { credentials: 'include' }),
        fetch('/api/admin/contracts/available-msisdn', { credentials: 'include' })
      ]);
      if (cRes.ok) contracts = await cRes.json();
      if (uRes.ok) customers = await uRes.json();
      if (pRes.ok) plans = await pRes.json();
      if (mRes.ok) availableMsisdns = await mRes.json();
      if (mRes.ok) availableMsisdns = await mRes.json();

      // Handle query params for direct provisioning
      const urlParams = new URLSearchParams(window.location.search);
      const cid = urlParams.get('customerId');
      if (cid) {
        const target = customers.find(u => u.id === parseInt(cid));
        if (target) {
          selectCustomer(target);
          showModal = true;
          // Clear param so it doesn't reopen on refresh
          window.history.replaceState({}, document.title, window.location.pathname);
        }
      }
    } catch {}
  }

  $effect(() => {
    loadData();
  });

  // Watch for data loading + query params
  $effect(() => {
    if (customers.length > 0 && !showModal) {
      const urlParams = new URLSearchParams(window.location.search);
      const cid = urlParams.get('customerId');
      if (cid) {
        const target = customers.find(u => u.id === parseInt(cid));
        if (target) {
          // Give the browser a moment to settle
          setTimeout(() => {
            selectCustomer(target);
            showModal = true;
            window.history.replaceState({}, document.title, window.location.pathname);
          }, 100);
        }
      }
    }
  });

  // Debounced server-side MSISDN search
  $effect(() => {
    clearTimeout(msisdnSearchTimer);
    msisdnSearchTimer = setTimeout(async () => {
      const term = msisdnSearch.trim();
      if (term === '') {
        // No search: show first 10 of available pool
        msisdnResults = availableMsisdns.slice(0, 10);
      } else {
        try {
          const res = await fetch(`/api/admin/contracts/available-msisdn?search=${encodeURIComponent(term)}`, { credentials: 'include' });
          if (res.ok) msisdnResults = await res.json();
        } catch (e) { console.error('MSISDN search error:', e); }
      }
    }, 300);
    return () => clearTimeout(msisdnSearchTimer);
  });

  function selectCustomer(u) {
    selectedCustomer = u;
    customerSearch = u.name;
    showDropdown = false;
  }

  function selectMsisdn(m) {
    newMsisdn = m.msisdn;
    msisdnSearch = m.msisdn;
    showMsisdnDropdown = false;
  }

  async function provisionLine(e) {
    e.preventDefault();
    if (!isNewCustomer && !selectedCustomer) { showToast("Please select a customer", 'error'); return; }
    if (isNewCustomer && (!newCustName || !newCustEmail)) { showToast("Please fill Name and Email", 'error'); return; }
    
    loading = true;
    try {
      let userId = selectedCustomer?.id;

      // Step 1: Create customer if it's a new one
      if (isNewCustomer) {
        const custRes = await fetch('/api/admin/customers', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            name: newCustName,
            email: newCustEmail,
            address: newCustAddress,
            birthdate: newCustBirthdate,
            msisdn: newMsisdn // Use the new MSISDN as the primary for user record
          })
        });
        if (!custRes.ok) throw new Error(await custRes.text());
        const custData = await custRes.json();
        userId = custData.id;
      }

      // Step 2: Provision the line
      const res = await fetch('/api/admin/contracts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          msisdn: newMsisdn,
          userId: userId,
          planId: selectedPlan,
          creditLimit: creditLimit
        })
      });
      if (res.ok) {
        showToast('Line provisioned successfully!');
        showModal = false;
        newMsisdn = '';
        msisdnSearch = '';
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
          {@const pName = (c.rateplanName || '').toLowerCase()}
          <tr>
            <td><span class="id-badge">#{c.id}</span></td>
            <td><span class="phone-num">{c.msisdn}</span></td>
            <td style="font-weight:600">{c.customerName||'—'}</td>
            <td>
              <span class="badge {pName.includes('basic') ? 'badge-plan-basic' : pName.includes('premium') ? 'badge-plan-premium' : pName.includes('elite') ? 'badge-plan-elite' : pName.includes('standard') ? 'badge-plan-standard' : 'badge-customer'}">
                {c.rateplanName || '—'}
              </span>
            </td>
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
      <div class="toggle-group" style="display:flex; gap:0.5rem; margin-bottom: 2rem; background: rgba(255,255,255,0.05); padding: 4px; border-radius: 12px;">
        <button type="button" class="btn {isNewCustomer ? 'btn-ghost' : 'btn-primary'}" style="flex:1" onclick={() => isNewCustomer = false}>Existing Customer</button>
        <button type="button" class="btn {isNewCustomer ? 'btn-primary' : 'btn-ghost'}" style="flex:1" onclick={() => isNewCustomer = true}>New Customer</button>
      </div>

      {#if !isNewCustomer}
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
      {:else}
        <div class="grid-2 animate-fade" style="gap:1rem; margin-bottom: 1rem;">
          <div class="form-group">
            <label class="label">Full Name</label>
            <input class="input" placeholder="Ahmed Ali" bind:value={newCustName} required />
          </div>
          <div class="form-group">
            <label class="label">Email Address</label>
            <input class="input" type="email" placeholder="ahmed@email.com" bind:value={newCustEmail} required />
          </div>
        </div>
        <div class="grid-2 animate-fade" style="gap:1rem; margin-bottom: 1rem;">
          <div class="form-group">
            <label class="label">Address (Optional)</label>
            <input class="input" placeholder="Cairo, Egypt" bind:value={newCustAddress} />
          </div>
          <div class="form-group">
            <label class="label">Birth Date</label>
            <input class="input" type="date" bind:value={newCustBirthdate} />
          </div>
        </div>
      {/if}
      </div>

      <div class="grid-2">
        <div class="form-group" style="position:relative">
          <label class="label">New MSISDN</label>
          <input 
            class="input" 
            placeholder="Search available pool..." 
            bind:value={msisdnSearch} 
            onfocus={() => showMsisdnDropdown = true}
            oninput={() => showMsisdnDropdown = true}
            required 
          />
           {#if showMsisdnDropdown && msisdnResults.length > 0}
             <div class="search-dropdown card animate-fade">
               {#each msisdnResults as m}
                 <button type="button" class="dropdown-item" onclick={() => selectMsisdn(m)}>
                   <span class="name">{m.msisdn}</span>
                   <span class="msisdn text-muted" style="font-size:0.7rem">AVAILABLE</span>
                 </button>
               {/each}
             </div>
           {/if}
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
  .badge.status-suspended { background: rgba(239, 68, 68, 0.1); color: #ef4444; border: 1px solid rgba(239, 68, 68, 0.2); }
  .badge.status-suspended_debt { background: rgba(245, 158, 11, 0.1); color: #f59e0b; border: 1px solid rgba(245, 158, 11, 0.2); }
  .badge.status-terminated { background: rgba(139, 92, 246, 0.1); color: #a78bfa; border: 1px solid rgba(139, 92, 246, 0.2); }
  .badge-plan-basic { 
    background: rgba(59, 130, 246, 0.1); 
    color: #60a5fa; 
    border: 1px solid rgba(59, 130, 246, 0.2);
    border-left: 3px solid #3b82f6;
  }
  .badge-plan-standard { 
    background: rgba(255, 255, 255, 0.05); 
    color: #cbd5e1; 
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-left: 3px solid #94a3b8;
  }
  .badge-plan-premium { 
    background: rgba(248, 113, 113, 0.1); 
    color: #fca5a5; 
    border: 1px solid rgba(248, 113, 113, 0.2);
    border-left: 3px solid #f87171;
  }
  .badge-plan-elite { 
    background: rgba(245, 158, 11, 0.1); 
    color: #fbbf24; 
    border: 1px solid rgba(245, 158, 11, 0.2);
    border-left: 3px solid #f59e0b;
  }
</style>
