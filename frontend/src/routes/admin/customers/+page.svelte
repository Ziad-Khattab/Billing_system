<script>
  let customers = $state([]);
  let search = $state('');
  let loading = $state(true);
  let showModal = $state(false);
  let newCustomer = $state({ name: '', email: '', msisdn: '', address: '', birthdate: '', category: 'Silver' });
  let error = $state('');
  let showSuccess = $state(false);

  async function load() {
    loading = true;
    const url = search ? `/api/admin/customers?q=${encodeURIComponent(search)}` : '/api/admin/customers';
    try { const res = await fetch(url, { credentials: 'include' }); if (res.ok) customers = await res.json(); } catch {}
    loading = false;
  }

  async function createCustomer(e) {
    e.preventDefault();
    error = '';
    try {
      const res = await fetch('/api/admin/customers', { 
        method: 'POST', 
        headers: { 'Content-Type': 'application/json' }, 
        credentials: 'include', 
        body: JSON.stringify(newCustomer) 
      });
      if (res.ok) { 
        showModal = false; 
        showSuccess = true;
        newCustomer = { name: '', email: '', msisdn: '', address: '', birthdate: '', category: 'Silver' }; 
        load(); 
      } else {
        const data = await res.json();
        error = data.message || 'Failed to create customer';
      }
    } catch (err) {
      error = 'Network error. Please try again.';
    }
  }

  $effect(() => { load(); });
</script>

<svelte:head><title>Customers — FMRZ Admin</title></svelte:head>
<div class="container">
  <div class="page-header">
    <h1>Customer <span class="text-gradient">Directory</span></h1>
    <p class="text-muted">Manage subscriber profiles and account information</p>
  </div>
  
  <div class="search-bar animate-fade">
    <div style="display:flex;gap:1rem">
      <input class="input" style="width:250px" placeholder="Search by name or email..." bind:value={search} oninput={() => setTimeout(load, 300)} aria-label="Search customers" />
      <button class="btn btn-primary" onclick={() => { showModal = true; error = ''; }}>+ Add New Customer</button>
    </div>
  </div>

  <div class="table-wrapper animate-fade"><table>
    <thead><tr><th>ID</th><th>MSISDN</th><th>Name</th><th>Category</th><th>Email</th><th>Address</th></tr></thead>
    <tbody>{#each customers as c}<tr>
      <td><span class="id-badge">#{c.id}</span></td>
      <td><span class="phone-num">{c.msisdn}</span></td>
      <td style="font-weight:600">{c.name}</td>
      <td><span class="badge badge-customer">{c.category}</span></td>
      <td class="text-muted">{c.email||'—'}</td>
      <td class="text-muted">{c.address||'—'}</td>
    </tr>{/each}</tbody>
  </table></div>
</div>

{#if showModal}
<div
  class="modal-overlay"
  role="button"
  tabindex="0"
  aria-label="Close dialog"
  onclick={() => showModal = false}
  onkeydown={(e) => { if (e.key === 'Escape' || e.key === 'Enter' || e.key === ' ') showModal = false; }}
>
<div
  class="modal card-glass animate-fade"
  role="dialog"
  tabindex="-1"
  aria-modal="true"
  aria-label="Add new customer"
  onclick={e => e.stopPropagation()}
  onkeydown={(e) => { if (e.key === 'Escape') showModal = false; }}
>
  <h2>Add New Customer</h2>
  {#if error}
    <div class="error-msg animate-fade">{error}</div>
  {/if}
  <form onsubmit={createCustomer}>
    <div class="form-group">
      <label class="label" for="c_msisdn">Primary MSISDN</label>
      <input id="c_msisdn" class="input" bind:value={newCustomer.msisdn} placeholder="010XXXXXXXX" required />
    </div>
    <div class="form-group">
      <label class="label" for="c_name">Full Name</label>
      <input id="c_name" class="input" bind:value={newCustomer.name} required />
    </div>
    <div class="form-group">
      <label class="label" for="c_category">Category</label>
      <select id="c_category" class="input" bind:value={newCustomer.category}>
        <option value="Gold">Gold</option>
        <option value="Silver">Silver</option>
        <option value="VIP">VIP</option>
      </select>
    </div>
    <div class="form-group">
      <label class="label" for="c_email">Email Address</label>
      <input id="c_email" class="input" type="email" bind:value={newCustomer.email} placeholder="ahmed@email.com" />
    </div>
    <div class="form-group">
      <label class="label" for="c_address">Mailing Address</label>
      <input id="c_address" class="input" bind:value={newCustomer.address} />
    </div>
    <div style="display:flex;gap:1rem;justify-content:flex-end"><button type="button" class="btn btn-secondary" onclick={() => showModal = false}>Cancel</button><button type="submit" class="btn btn-primary">Create Customer</button></div>
  </form>
</div></div>
{/if}

{#if showSuccess}
<div class="modal-overlay" onclick={() => showSuccess = false} role="button" tabindex="0" onkeydown={null}>
  <div class="modal card-glass animate-fade" onclick={e => e.stopPropagation()} role="dialog">
    <div style="text-align:center;padding:1rem">
      <div style="font-size:3rem;margin-bottom:1rem">✅</div>
      <h2>Profile Created!</h2>
      <p class="text-muted" style="margin-bottom:2rem">The customer profile has been successfully saved to the database.</p>
      <div style="display:flex;flex-direction:column;gap:1rem">
        <a href="/admin/contracts" class="btn btn-primary">Go to Contracts to assign MSISDN</a>
        <button class="btn btn-secondary" onclick={() => showSuccess = false}>Stay on Customers</button>
      </div>
    </div>
  </div>
</div>
{/if}

<style>
  .modal-overlay{position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;z-index:200;backdrop-filter:blur(4px)}
  .modal{width:100%;max-width:450px;padding:2rem}
  .modal h2{margin-bottom:1.5rem}
</style>
