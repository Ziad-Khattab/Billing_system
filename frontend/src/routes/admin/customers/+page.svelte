<script>
  let customers = $state([]);
  let search = $state('');
  let loading = $state(true);
  let showModal = $state(false);
  let newCustomer = $state({ name: '', email: '', address: '', birthdate: '' });

  async function load() {
    loading = true;
    const url = search ? `/api/admin/customers?q=${encodeURIComponent(search)}` : '/api/admin/customers';
    try { const res = await fetch(url, { credentials: 'include' }); if (res.ok) customers = await res.json(); } catch {}
    loading = false;
  }

  async function createCustomer(e) {
    e.preventDefault();
    try {
      const res = await fetch('/api/admin/customers', { method: 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'include', body: JSON.stringify(newCustomer) });
      if (res.ok) { showModal = false; newCustomer = { name: '', email: '', address: '', birthdate: '' }; load(); }
    } catch {}
  }

  $effect(() => { load(); });
</script>

<svelte:head><title>Customers — FMRZ Admin</title></svelte:head>
<div class="container">
  <div class="page-header">
    <h1>Customers</h1>
    <div style="display:flex;gap:1rem">
      <input class="input" style="width:250px" placeholder="Search..." bind:value={search} oninput={() => setTimeout(load, 300)} />
      <button class="btn btn-primary" onclick={() => showModal = true}>+ Add</button>
    </div>
  </div>
  <div class="table-wrapper"><table>
    <thead><tr><th>ID</th><th>Name</th><th>Email</th><th>Address</th><th>Birthdate</th></tr></thead>
    <tbody>{#each customers as c}<tr><td>#{c.id}</td><td style="font-weight:600">{c.name}</td><td>{c.email||'—'}</td><td>{c.address||'—'}</td><td>{c.birthdate||'—'}</td></tr>{/each}</tbody>
  </table></div>
</div>

{#if showModal}
<div class="modal-overlay" onclick={() => showModal = false}><div class="modal card-glass animate-fade" onclick={e => e.stopPropagation()}>
  <h2>Add New Customer</h2>
  <form onsubmit={createCustomer}>
    <div class="form-group"><label class="label">Full Name</label><input class="input" bind:value={newCustomer.name} required /></div>
    <div class="form-group"><label class="label">Email Address</label><input class="input" type="email" bind:value={newCustomer.email} placeholder="ahmed@email.com" /></div>
    <div class="form-group"><label class="label">Mailing Address</label><input class="input" bind:value={newCustomer.address} /></div>
    <div class="form-group"><label class="label">Birthdate</label><input class="input" type="date" bind:value={newCustomer.birthdate} /></div>
    <div style="display:flex;gap:1rem;justify-content:flex-end"><button type="button" class="btn btn-secondary" onclick={() => showModal = false}>Cancel</button><button type="submit" class="btn btn-primary">Create Customer</button></div>
  </form>
</div></div>
{/if}

<style>
  .modal-overlay{position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;z-index:200;backdrop-filter:blur(4px)}
  .modal{width:100%;max-width:450px;padding:2rem}
  .modal h2{margin-bottom:1.5rem}
</style>
