<script>
  /** @type {import('./$types').PageData} */
  let { data } = $props();

  let contract = $state(null);
  let activeAddons = $state([]);
  let availableAddons = $state([]);
  let loading = $state(true);
  let showAddonModal = $state(false);
  let selectedAddon = $state(null);
  let purchasing = $state(false);

  async function loadData() {
    try {
      const contractId = data.contractId;
      const [contractRes, activeRes, availableRes] = await Promise.all([
        fetch(`/api/admin/contracts/${contractId}`, { credentials: 'include' }),
        fetch(`/api/admin/addons/${contractId}`, { credentials: 'include' }),
        fetch('/api/admin/addons', { credentials: 'include' })
      ]);

      if (contractRes.ok) contract = await contractRes.json();
      if (activeRes.ok) activeAddons = await activeRes.json();
      if (availableRes.ok) availableAddons = await availableRes.json();
    } catch (e) {
      console.error('Failed to load data:', e);
    } finally {
      loading = false;
    }
  }

  async function purchaseAddon() {
    if (!selectedAddon || !contract) return;

    purchasing = true;
    try {
      const res = await fetch(`/api/admin/contracts/${contract.id}/addons`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ addonId: selectedAddon.id })
      });

      if (res.ok) {
        showAddonModal = false;
        selectedAddon = null;
        loadData();
      } else {
        alert('Failed to purchase addon');
      }
    } catch (e) {
      alert('Error: ' + e.message);
    } finally {
      purchasing = false;
    }
  }

  async function cancelAddon(addonId) {
    if (!confirm('Cancel this addon?')) return;

    try {
      const res = await fetch(`/api/admin/contracts/${contract.id}/addons/${addonId}`, {
        method: 'DELETE',
        credentials: 'include'
      });

      if (res.ok) {
        loadData();
      } else {
        alert('Failed to cancel addon');
      }
    } catch (e) {
      alert('Error: ' + e.message);
    }
  }

  $effect(() => { loadData(); });
</script>

<svelte:head><title>Contract Details — FMRZ Admin</title></svelte:head>

<div class="container">
  <div class="page-header">
    <div>
      <h1>Contract <span class="text-gradient">Details</span></h1>
      <p class="text-muted">View and manage contract addons and services</p>
    </div>
  </div>

  {#if loading}
    <div style="text-align: center; padding: 2rem;">Loading...</div>
  {:else if contract}
    <div class="contract-details card animate-fade">
      <div class="detail-section">
        <h2>Contract Information</h2>
        <div class="detail-grid">
          <div class="detail-item">
            <span class="label">MSISDN</span>
            <span class="value">{contract.msisdn}</span>
          </div>
          <div class="detail-item">
            <span class="label">Customer</span>
            <span class="value">{contract.customerName}</span>
          </div>
          <div class="detail-item">
            <span class="label">Rate Plan</span>
            <span class="value">{contract.rateplanName}</span>
          </div>
          <div class="detail-item">
            <span class="label">Status</span>
            <span class="value badge badge-{contract.status}">{contract.status}</span>
          </div>
          <div class="detail-item">
            <span class="label">Available Credit</span>
            <span class="value amount">{contract.availableCredit} EGP</span>
          </div>
        </div>
      </div>

      <div class="addons-section">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
          <h2>Active Addons</h2>
          <button class="btn btn-primary" onclick={() => showAddonModal = true}>+ Add Addon</button>
        </div>

        {#if activeAddons.length > 0}
          <div class="addons-list">
            {#each activeAddons as addon}
              <div class="addon-card">
                <div class="addon-header">
                  <h3>{addon.name}</h3>
                  <button class="btn-close" onclick={() => cancelAddon(addon.id)}>✕</button>
                </div>
                <p class="addon-description">{addon.description}</p>
                <div class="addon-info">
                  <span>Price: <strong>{addon.price} EGP</strong></span>
                  <span>Expires: <strong>{new Date(addon.expiry_date).toLocaleDateString()}</strong></span>
                </div>
              </div>
            {/each}
          </div>
        {:else}
          <p class="text-muted" style="text-align: center; padding: 2rem;">No active addons. Click "+ Add Addon" to purchase one.</p>
        {/if}
      </div>
    </div>

    {#if showAddonModal}
      <div class="modal-overlay" onclick={() => showAddonModal = false}>
        <div class="modal card-glass" onclick={e => e.stopPropagation()}>
          <h2>Purchase Addon</h2>
          <div class="addons-grid">
            {#each availableAddons as addon}
              <div
                class="addon-option {selectedAddon?.id === addon.id ? 'selected' : ''}"
                onclick={() => selectedAddon = addon}
              >
                <h3>{addon.name}</h3>
                <p>{addon.description}</p>
                <div class="addon-price">{addon.price} EGP</div>
              </div>
            {/each}
          </div>
          <div style="display: flex; gap: 1rem; justify-content: flex-end; margin-top: 2rem;">
            <button class="btn btn-secondary" onclick={() => showAddonModal = false}>Cancel</button>
            <button
              class="btn btn-primary"
              onclick={purchaseAddon}
              disabled={!selectedAddon || purchasing}
            >
              {purchasing ? 'Purchasing...' : 'Purchase Addon'}
            </button>
          </div>
        </div>
      </div>
    {/if}
  {/if}
</div>

<style>
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }

  .contract-details { padding: 2.5rem; }

  .detail-section { margin-bottom: 3rem; }
  .detail-section h2 { margin-bottom: 1.5rem; font-size: 1.25rem; font-weight: 700; }

  .detail-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 2rem; }

  .detail-item { display: flex; flex-direction: column; }
  .detail-item .label { color: var(--text-muted); font-size: 0.85rem; margin-bottom: 0.5rem; }
  .detail-item .value { font-weight: 600; font-size: 1.1rem; }
  .detail-item .amount { color: #22C55E; }

  .addons-section h2 { margin-bottom: 1.5rem; font-size: 1.25rem; font-weight: 700; }

  .addons-list { display: grid; gap: 1.5rem; }

  .addon-card {
    padding: 1.5rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border);
    border-radius: 12px;
    transition: all 0.3s;
  }
  .addon-card:hover { border-color: var(--red); background: rgba(255, 255, 255, 0.08); }

  .addon-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; }
  .addon-header h3 { margin: 0; font-size: 1.1rem; }

  .btn-close { background: none; border: none; color: var(--text-muted); cursor: pointer; font-size: 1.2rem; }
  .btn-close:hover { color: var(--red); }

  .addon-description { color: var(--text-secondary); margin: 0.5rem 0; }

  .addon-info { display: flex; gap: 2rem; font-size: 0.9rem; }
  .addon-info span { color: var(--text-secondary); }

  .addons-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin: 1.5rem 0; }

  .addon-option {
    padding: 1.5rem;
    border: 2px solid var(--border);
    border-radius: 12px;
    cursor: pointer;
    transition: all 0.3s;
    background: rgba(255, 255, 255, 0.02);
  }
  .addon-option:hover { border-color: var(--red); }
  .addon-option.selected { border-color: var(--red); background: rgba(224, 8, 0, 0.1); }

  .addon-option h3 { margin: 0 0 0.5rem 0; font-size: 1rem; }
  .addon-option p { margin: 0 0 1rem 0; color: var(--text-secondary); font-size: 0.85rem; }
  .addon-price { font-weight: 700; color: var(--red); }

  .modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; z-index: 200; backdrop-filter: blur(4px); }
  .modal { width: 100%; max-width: 600px; padding: 2rem; }

  .badge { padding: 0.25rem 0.75rem; border-radius: 6px; font-size: 0.8rem; font-weight: 600; }
  .badge-active { background: rgba(34, 197, 94, 0.1); color: #22C55E; }
  .badge-suspended { background: rgba(245, 158, 11, 0.1); color: #F59E0B; }
  .badge-terminated { background: rgba(239, 68, 68, 0.1); color: #EF4444; }
</style>

