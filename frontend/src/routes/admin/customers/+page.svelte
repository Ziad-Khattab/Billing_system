<script>
  import { showToast } from '$lib/toast.svelte.js';
  import { authState } from '$lib/auth.svelte.js';
  import Modal from '$lib/components/Modal.svelte';
  let customers = $state([]);
  let total = $state(0);
  let search = $state('');
  let page = $state(0);
  let limit = $state(50);
  let jumpPage = $state(1);
  let showModal = $state(false);
  let loading = $state(false);
  let createLoading = $state(false);
  let newCustomer = $state({ name: '', email: '', username: '', address: '', birthdate: '' });

  const totalPages = $derived(Math.ceil(total / limit));

  async function load() {
    loading = true;
    try {
      const offset = page * limit;
      const res = await fetch(`/api/admin/customers?search=${search}&limit=${limit}&offset=${offset}`);
      if (res.ok) {
        const result = await res.json();
        customers = result.data || [];
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
      load();
    }, 300);
  }

  function nextPage() { if ((page + 1) * limit < total) { page++; load(); } }
  function prevPage() { if (page > 0) { page--; load(); } }
  function goToPage() {
    const target = Math.max(1, Math.min(jumpPage, totalPages));
    page = target - 1;
    load();
  }
  function handleLimitChange() {
    page = 0;
    load();
  }

  async function createCustomer(e) {
    e.preventDefault();
    createLoading = true;
    try {
      const res = await fetch('/api/admin/customers', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newCustomer)
      });
      if (res.ok) {
        showToast('Customer profile created successfully!');
        showModal = false;
        newCustomer = { name: '', email: '', username: '', address: '', birthdate: '' };
        page = 0;
        load();
      } else {
        const msg = await res.text();
        showToast(msg || 'Failed to create customer', 'error');
      }
    } catch (e) {
      showToast('Connection error', 'error');
    } finally {
      createLoading = false;
    }
  }

  $effect(() => {
    load();
  });
</script>

<svelte:head>
  <title>Customers — FMRZ</title>
</svelte:head>

<div class="container">
  <div class="page-header">
    <h1>Customer <span class="text-gradient">Directory</span></h1>
    <p class="text-muted">Manage subscriber profiles and account information</p>
  </div>
  
  <div class="search-bar animate-fade">
    <div style="display:flex;gap:1rem">
      <div class="relative group" style="position: relative;">
        <span style="position: absolute; left: 12px; top: 50%; transform: translateY(-50%); color: #64748b;">
           <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
        </span>
        <input 
          class="input" 
          style="width:300px; padding-left: 2.5rem;" 
          placeholder="Search directory..." 
          bind:value={search} 
          oninput={handleSearch}
          aria-label="Search customers" 
        />
      </div>
      <button class="btn btn-primary" style="display: flex; align-items: center; gap: 8px; padding: 0.75rem 1.5rem;" onclick={() => { showModal = true; }}>
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
        Add New Customer
      </button>
    </div>
  </div>

  <div class="table-wrapper static-table animate-fade">
    {#if loading}
      <div class="loading-state">
        <div class="spinner"></div>
        <p>Loading directory...</p>
      </div>
    {:else}
      {#if customers.length === 0}
        <div class="empty-state">
          <p>No customers found matching your search.</p>
        </div>
      {:else}
        <table>
          <thead>
            <tr><th>ID</th><th>Username</th><th>Name</th><th>Email</th><th>Address</th><th>Actions</th></tr>
          </thead>
          <tbody>
            {#each customers as c}
              <tr>
                <td><span class="id-badge">#{c.id}</span></td>
                <td><span class="phone-num" style="color: var(--red) !important;">{c.username}</span></td>
                <td class="customer-name" style="color: #FFFFFF !important;">{c.name}</td>
                <td style="color: #94A3B8 !important; font-size: 0.9rem; font-weight: 500;">{c.email||'—'}</td>
                <td style="color: #FB7185 !important; font-size: 0.9rem; font-weight: 500;">{c.address||'—'}</td>
                <td>
                  <button class="btn btn-secondary btn-sm" style="font-size: 0.7rem; border-color: var(--red); color: var(--red-light);" onclick={() => window.location.href = `/admin/contracts?customerId=${c.id}`}>
                    Provision Line
                  </button>
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
          <span class="total-info">Total: {total} customers</span>
        </div>
      </div>
    {/if}
  </div>
</div>

  <Modal bind:show={showModal} title="Add New Customer" type="admin">
    <form onsubmit={createCustomer}>
      <div class="form-group">
        <label class="label">Full Name</label>
        <input class="input" bind:value={newCustomer.name} placeholder="Ahmed Ali" required />
      </div>
      <div class="form-group">
        <label class="label">Email Address (Unique)</label>
        <input class="input" type="email" bind:value={newCustomer.email} placeholder="ahmed@email.com" required />
      </div>
      <div class="form-group">
        <label class="label">Username (Primary Identification)</label>
        <input 
          class="input" 
          bind:value={newCustomer.username} 
          placeholder="e.g. jdoe123" 
          pattern="^(?!\d+$).+" 
          title="Username cannot be numbers only"
          required 
        />
      </div>
      <div class="form-group">
        <label class="label">Mailing Address</label>
        <input class="input" bind:value={newCustomer.address} placeholder="123 Street, City" />
      </div>
      <div class="form-group">
        <label class="label">Birth Date</label>
        <input class="input" type="date" bind:value={newCustomer.birthdate} />
      </div>
      <div style="display:flex;gap:1rem;justify-content:flex-end;margin-top:2rem">
        <button type="button" class="btn btn-secondary" onclick={() => showModal = false}>Cancel</button>
        <button type="submit" class="btn btn-primary" disabled={createLoading}>
          {createLoading ? 'Creating...' : 'Create Profile'}
        </button>
      </div>
    </form>
  </Modal>


<style>
  .static-table {
    margin-top: 2rem;
    background: rgba(15, 15, 25, 0.6);
    border: 1px solid var(--border);
    border-radius: 20px;
    overflow: hidden;
    transition: none !important;
    transform: none !important;
    box-shadow: var(--shadow-premium);
  }
  
  .static-table:hover {
    background: rgba(15, 15, 25, 0.6) !important;
    transform: none !important;
    border-color: var(--border) !important;
    box-shadow: var(--shadow-premium) !important;
  }

  table { width: 100%; border-collapse: collapse; border: none; }
  th { text-align: left; padding: 1rem; background: rgba(255, 255, 255, 0.05); color: #cbd5e1; font-weight: 600; border-bottom: 1px solid var(--border); }
  td { padding: 1rem; border-bottom: 1px solid var(--border); }
  tr:last-child td { border-bottom: none; }
  
  .id-badge { background: rgba(255, 255, 255, 0.05); padding: 0.2rem 0.5rem; border-radius: 6px; font-size: 0.8rem; color: #94a3b8; }
  .phone-num { font-family: 'JetBrains Mono', monospace; font-weight: 600; }
  .customer-name { font-weight: 700; font-size: 1.05rem; }

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
  .btn-page { background: rgba(255, 255, 255, 0.05); color: white; border: 1px solid var(--border); padding: 0.5rem 1rem; border-radius: 8px; font-weight: 600; cursor: pointer; transition: all 0.2s; }
  .btn-page:hover:not(:disabled) { background: rgba(255, 255, 255, 0.1); border-color: var(--red); }
  .btn-page:disabled { opacity: 0.4; cursor: not-allowed; }

  .loading-state, .empty-state { padding: 4rem; text-align: center; color: var(--text-muted); }
  .spinner { width: 40px; height: 40px; border: 4px solid rgba(224, 8, 0, 0.1); border-top-color: var(--red); border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 1rem; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
