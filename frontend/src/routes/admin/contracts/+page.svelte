<script>
  import { showToast } from '$lib/toast.svelte.js';
  import { authState } from '$lib/auth.svelte.js';
  import Modal from '$lib/components/Modal.svelte';
  let contracts = $state([]);
  let total = $state(0);
  let page = $state(0);
  let limit = $state(50);
  let jumpPage = $state(1);
  let search = $state('');
  let customers = $state([]);
  let plans = $state([]);
  let loading = $state(false);
  let showModal = $state(false);
  let customerSearch = $state('');
  let showDropdown = $state(false);
  let showPlanDropdown = $state(false);

  const totalPages = $derived(Math.ceil(total / limit));

  async function loadContracts() {
    loading = true;
    try {
      const offset = page * limit;
      const res = await fetch(`/api/admin/contracts?search=${search}&limit=${limit}&offset=${offset}`, { credentials: 'include' });
      if (res.ok) {
        const result = await res.json();
        contracts = result.data || [];
        total = result.total || 0;
        jumpPage = page + 1;
      }
    } finally {
      loading = false;
    }
  }

  function handleSearch() {
    clearTimeout(window.searchTimeout);
    window.searchTimeout = setTimeout(() => {
      page = 0;
      loadContracts();
    }, 300);
  }

  function nextPage() { if ((page + 1) * limit < total) { page++; loadContracts(); } }
  function prevPage() { if (page > 0) { page--; loadContracts(); } }
  function goToPage() {
    const target = Math.max(1, Math.min(jumpPage, totalPages));
    page = target - 1;
    loadContracts();
  }
  function handleLimitChange() {
    page = 0;
    loadContracts();
  }

  let filteredCustomers = $derived(
    customers
      .filter((u, index, self) => index === self.findIndex(t => t.id === u.id)) // Deduplicate by ID
      .filter(u => 
        (u.name && u.name.toLowerCase().includes(customerSearch.toLowerCase())) || 
        (u.msisdn && u.msisdn.includes(customerSearch))
      ).slice(0, 10)
  );

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
    loadContracts(); // Paginated load
    try {
      const [uRes, pRes, mRes] = await Promise.all([
        fetch('/api/admin/customers?limit=1000', { credentials: 'include' }), // For dropdown search
        fetch('/api/admin/rateplans', { credentials: 'include' }),
        fetch('/api/admin/contracts/available-msisdn', { credentials: 'include' })
      ]);
      if (uRes.ok) {
        const uData = await uRes.json();
        customers = uData.data || uData; // Handle both wrapper or list
      }
      if (pRes.ok) plans = await pRes.json();
      if (mRes.ok) availableMsisdns = await mRes.json();
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

  $effect(() => {
    if (!showModal) {
      showDropdown = false;
      showMsisdnDropdown = false;
      showPlanDropdown = false;
    }
  });

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

  <div class="search-bar animate-fade">
    <div class="input-group">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
      <input type="text" bind:value={search} oninput={handleSearch} placeholder="Search MSISDN or Customer..." />
    </div>
  </div>

  <div class="table-wrapper animate-fade">
    {#if loading}
      <div class="loading-state">
        <div class="spinner"></div>
        <p>Loading contracts...</p>
      </div>
    {:else}
      {#if contracts.length === 0}
        <div class="empty-state">
          <p>No contracts found matching your search.</p>
        </div>
      {:else}
        <table>
          <thead>
            <tr><th>ID</th><th>MSISDN</th><th>Customer</th><th>Plan</th><th>Status</th><th>Credit</th></tr>
          </thead>
          <tbody>
            {#each contracts as c}
              {@const pName = (c.rateplan_name || c.rateplanName || '').toLowerCase()}
              <tr>
                <td><span class="id-badge">#{c.id}</span></td>
                <td><span class="phone-num">{c.msisdn}</span></td>
                <td style="font-weight:600; color: #FFFFFF">{c.customer_name || c.customerName || '—'}</td>
                <td>
                  <span class="badge {pName.includes('gold') ? 'badge-plan-gold' : pName.includes('premium') ? 'badge-plan-premium' : pName.includes('elite') ? 'badge-plan-elite' : pName.includes('standard') ? 'badge-plan-standard' : pName.includes('basic') ? 'badge-plan-basic' : 'badge-customer'}">
                    {c.rateplan_name || c.rateplanName || '—'}
                  </span>
                </td>
                <td>
                  <span class="badge status-{c.status?.toLowerCase().replace(' ', '_') || 'active'}">
                    {c.status === 'suspended_debt' ? 'Suspended (Debt)' : c.status === 'suspended' ? 'On Hold' : c.status === 'terminated' ? 'Deactivated' : (c.status || 'Active')}
                  </span>
                </td>
                <td>
                  <span class="amount-num" style={(c.available_credit || c.availableCredit) < 0 ? 'color: #ef4444' : ''}>
                    {c.available_credit || c.availableCredit} EGP
                  </span>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      {/if}

      <div class="pagination">
        <div class="pagination-controls">
          <button class="btn-page" onclick={prevPage} disabled={page === 0}>Previous</button>
          <div class="page-jump">
            <span>Page</span>
            <input type="number" bind:value={jumpPage} min="1" max={totalPages} class="input-jump" />
            <span>of {totalPages}</span>
            <button class="btn-go" onclick={goToPage}>Go</button>
          </div>
          <button class="btn-page" onclick={nextPage} disabled={(page + 1) * limit >= total}>Next</button>
        </div>
        <div class="pagination-settings">
          <span>Rows:</span>
          <select bind:value={limit} onchange={handleLimitChange} class="select-limit">
            <option value="25">25</option>
            <option value="50">50</option>
            <option value="75">75</option>
            <option value="100">100</option>
          </select>
          <span class="total-info">Total: {total} contracts</span>
        </div>
      </div>
    {/if}
  </div>
</div>

  <Modal bind:show={showModal} title="Provision New Line" type="admin">
    <form onsubmit={provisionLine}>
      <div class="form-group" style="position:relative">
      <div class="toggle-group" style="display:flex; gap:0.5rem; margin-bottom: 2rem; background: rgba(255,255,255,0.05); padding: 4px; border-radius: 12px;">
        <button type="button" class="btn {isNewCustomer ? 'btn-ghost' : 'btn-primary'}" style="flex:1" onclick={() => { isNewCustomer = false; showDropdown = false; showMsisdnDropdown = false; }}>Existing Customer</button>
        <button type="button" class="btn {isNewCustomer ? 'btn-primary' : 'btn-ghost'}" style="flex:1" onclick={() => { isNewCustomer = true; showDropdown = false; showMsisdnDropdown = false; }}>New Customer</button>
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
            onblur={() => setTimeout(() => showDropdown = false, 200)}
          />
          {#if showDropdown && filteredCustomers.length > 0}
            <div class="search-dropdown card animate-fade">
              <div class="dropdown-header" style="padding: 8px 16px; font-size: 0.7rem; color: var(--text-muted); border-bottom: 1px solid var(--border); background: rgba(255,255,255,0.02)">
                Showing top matches
              </div>
              {#each filteredCustomers as u}
                {@const pName = (u.rateplan_name || u.rateplanName || '').toLowerCase()}
                {@const badgeClass = pName.includes('gold') ? 'badge-plan-gold' : pName.includes('premium') ? 'badge-plan-premium' : pName.includes('elite') ? 'badge-plan-elite' : pName.includes('standard') ? 'badge-plan-standard' : 'badge-customer'}
                <button type="button" class="dropdown-item" onclick={() => selectCustomer(u)} style="display:flex; justify-content:space-between; align-items:center; padding: 12px 16px;">
                  <div style="display:flex; flex-direction:column; gap: 2px;">
                    <span class="name" style="font-weight: 700;">{u.name}</span>
                    <span class="msisdn" style="font-family: 'JetBrains Mono', monospace; font-size:0.75rem; color: #EF4444">{u.msisdn || 'NEW CUSTOMER'}</span>
                  </div>
                  {#if u.msisdn}
                    <span class="badge {badgeClass}" style="font-size:0.55rem; padding: 2px 8px; border-radius: 6px;">{u.rateplan_name || u.rateplanName || ''}</span>
                  {/if}
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
            onblur={() => setTimeout(() => showMsisdnDropdown = false, 200)}
            required 
          />
            {#if showMsisdnDropdown && msisdnResults.length > 0}
              <div class="search-dropdown card animate-fade">
                <div class="dropdown-header" style="padding: 8px 16px; font-size: 0.7rem; color: var(--text-muted); border-bottom: 1px solid var(--border); background: rgba(255,255,255,0.02)">
                  Showing top {msisdnResults.length} available numbers
                </div>
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

      <div class="form-group" style="position:relative">
        <label class="label">Select Rate Plan</label>
        <input 
          class="input" 
          placeholder="Choose a plan..." 
          value={plans.find(p => p.id === selectedPlan)?.name || ''} 
          readonly
          onfocus={() => showPlanDropdown = true}
          onblur={() => setTimeout(() => showPlanDropdown = false, 200)}
          style="cursor: pointer;"
        />
        {#if showPlanDropdown && plans.length > 0}
          <div class="search-dropdown card animate-fade">
            <div class="dropdown-header" style="padding: 8px 16px; font-size: 0.7rem; color: var(--text-muted); border-bottom: 1px solid var(--border); background: rgba(255,255,255,0.02)">
              Available Rate Plans
            </div>
            {#each plans as p}
              {@const pNameLower = p.name.toLowerCase()}
              {@const badgeClass = pNameLower.includes('gold') ? 'badge-plan-gold' : pNameLower.includes('premium') ? 'badge-plan-premium' : pNameLower.includes('elite') ? 'badge-plan-elite' : pNameLower.includes('standard') ? 'badge-plan-standard' : pNameLower.includes('basic') ? 'badge-plan-basic' : 'badge-customer'}
              <button type="button" class="dropdown-item" onclick={() => { selectedPlan = p.id; showPlanDropdown = false; }}>
                <div style="display:flex; flex-direction:column; gap: 2px;">
                  <span class="name">{p.name}</span>
                  <span class="msisdn text-muted" style="font-size:0.75rem">{p.price} EGP / month</span>
                </div>
                <span class="badge {badgeClass}" style="font-size:0.55rem; padding: 2px 8px; border-radius: 6px;">{p.name.split(' ')[0]}</span>
              </button>
            {/each}
          </div>
        {/if}
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
  .search-bar { margin-bottom: 2rem; max-width: 400px; }
  .input-group { position: relative; display: flex; align-items: center; }
  .input-group svg { position: absolute; left: 1rem; color: var(--text-muted); }
  .input-group input { width: 100%; padding: 0.8rem 1rem 0.8rem 3rem; background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border); border-radius: 12px; color: white; transition: all 0.3s; }
  .input-group input:focus { outline: none; border-color: var(--red); box-shadow: 0 0 15px rgba(224, 8, 0, 0.2); }

  .pagination { display: flex; flex-direction: column; align-items: center; gap: 1rem; padding: 1.5rem; border-top: 1px solid var(--border); background: rgba(255, 255, 255, 0.02); }
  .pagination-controls { display: flex; align-items: center; gap: 1.5rem; }
  .pagination-settings { display: flex; align-items: center; gap: 1rem; font-size: 0.85rem; color: var(--text-muted); }
  .page-jump { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: var(--text-muted); font-size: 0.9rem; }
  .input-jump { width: 60px; padding: 0.3rem 0.5rem; background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border); border-radius: 6px; color: white; text-align: center; }
  .btn-go { background: var(--red); color: white; border: none; padding: 0.3rem 0.8rem; border-radius: 6px; font-weight: 600; cursor: pointer; transition: 0.2s; }
  .btn-go:hover { background: var(--red-light); }
  .select-limit { background: rgba(255, 255, 255, 0.05); color: white; border: 1px solid var(--border); border-radius: 6px; padding: 0.2rem 0.5rem; outline: none; }
  .select-limit:focus { border-color: var(--red); }
  .total-info { margin-left: 1rem; font-style: italic; }
  .loading-state, .empty-state { padding: 4rem; text-align: center; color: var(--text-muted); }
  .spinner { width: 40px; height: 40px; border: 4px solid rgba(224, 8, 0, 0.1); border-top-color: var(--red); border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 1rem; }
  @keyframes spin { to { transform: rotate(360deg); } }

  .status-active { background: rgba(34, 197, 94, 0.1); color: #22C55E; border: 1px solid rgba(34, 197, 94, 0.2); text-transform: capitalize; font-weight: 700; padding: 4px 12px; border-radius: 8px; }
  .status-suspended { background: rgba(245, 158, 11, 0.1); color: #F59E0B; border: 1px solid rgba(245, 158, 11, 0.2); text-transform: capitalize; font-weight: 700; padding: 4px 12px; border-radius: 8px; }
  .status-suspended_debt { background: rgba(239, 68, 68, 0.1); color: #EF4444; border: 1px solid rgba(239, 68, 68, 0.2); text-transform: capitalize; font-weight: 700; padding: 4px 12px; border-radius: 8px; }
  .status-terminated { background: rgba(168, 85, 247, 0.1); color: #A855F7; border: 1px solid rgba(168, 85, 247, 0.2); text-transform: capitalize; font-weight: 700; padding: 4px 12px; border-radius: 8px; }
  .status-pending { background: rgba(59, 130, 246, 0.1); color: #3B82F6; border: 1px solid rgba(59, 130, 246, 0.2); text-transform: capitalize; font-weight: 700; padding: 4px 12px; border-radius: 8px; }

  /* Search Dropdown Refinement */
  .search-dropdown {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    z-index: 100;
    margin-top: 0.5rem;
    max-height: 300px;
    overflow-y: auto;
    background: #0a0a0f !important; /* Force solid dark background */
    border: 1px solid var(--border);
    box-shadow: 0 15px 40px rgba(0,0,0,0.8);
    transform: none !important; /* Disable global card hover rise */
  }

  .dropdown-item {
    width: 100%;
    background: transparent;
    border: none;
    border-bottom: 1px solid rgba(255,255,255,0.05);
    color: white;
    text-align: left;
    cursor: pointer;
    transition: all 0.2s;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    transform: none !important; /* Disable any inherited rise */
  }

  .dropdown-item:last-child { border-bottom: none; }

  .dropdown-item:hover {
    background: rgba(255, 255, 255, 0.08) !important;
    border-left: 4px solid var(--red);
    padding-left: 12px; /* Compensate for border */
  }

  .dropdown-item .name {
    font-weight: 700;
    font-size: 0.95rem;
  }

  .dropdown-item .msisdn {
    font-family: 'JetBrains Mono', monospace;
    font-size: 0.75rem;
  }
</style>
