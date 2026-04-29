<script>
  import { onMount } from 'svelte';
  import { fade, fly } from 'svelte/transition';
  import { showToast } from '$lib/toast.svelte.js';
  import Modal from '$lib/components/Modal.svelte';

  let rateplans = $state([]);
  let allPackages = $state([]);
  let loading = $state(true);
  let showModal = $state(false);
  let isEditing = $state(false);
  let currentPlan = $state({
    name: '',
    ror_voice: 0.10,
    ror_data: 0.25,
    ror_sms: 0.05,
    price: 0,
    servicePackageIds: []
  });

  async function fetchData() {
    loading = true;
    try {
      const [planRes, pkgRes] = await Promise.all([
        fetch('/api/admin/rateplans'),
        fetch('/api/admin/service-packages')
      ]);
      if (planRes.ok) rateplans = await planRes.json();
      if (pkgRes.ok) allPackages = await pkgRes.json();
    } catch (e) {
      showToast('Failed to fetch data', 'error');
    } finally {
      loading = false;
    }
  }

  function openCreateModal() {
    isEditing = false;
    currentPlan = {
      name: '',
      ror_voice: 0.10,
      ror_data: 0.25,
      ror_sms: 0.05,
      price: 0,
      servicePackageIds: []
    };
    showModal = true;
  }

  async function openEditModal(plan) {
    isEditing = true;
    // Fetch details to get current linked packages
    try {
        const res = await fetch(`/api/admin/rateplans/${plan.id}`);
        if (res.ok) {
            const details = await res.json();
            currentPlan = { 
                ...plan, 
                servicePackageIds: details.servicePackageIds || [] 
            };
        } else {
            currentPlan = { ...plan, servicePackageIds: [] };
        }
    } catch (e) {
        currentPlan = { ...plan, servicePackageIds: [] };
    }
    showModal = true;
  }

  function togglePackage(id) {
    if (currentPlan.servicePackageIds.includes(id)) {
      currentPlan.servicePackageIds = currentPlan.servicePackageIds.filter(pid => pid !== id);
    } else {
      currentPlan.servicePackageIds = [...currentPlan.servicePackageIds, id];
    }
  }

  async function savePlan() {
    const url = isEditing ? `/api/admin/rateplans/${currentPlan.id}` : '/api/admin/rateplans';
    const method = isEditing ? 'PUT' : 'POST';
    try {
      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(currentPlan)
      });
      if (res.ok) {
        showToast(`Rate plan ${isEditing ? 'updated' : 'created'} successfully`);
        showModal = false;
        fetchData();
      } else {
        const data = await res.json();
        showToast(data.message || 'Action failed', 'error');
      }
    } catch (e) {
      showToast('Connection error', 'error');
    }
  }

  async function deletePlan(id) {
    if (!confirm('Are you sure you want to delete this rate plan?')) return;
    try {
      const res = await fetch(`/api/admin/rateplans/${id}`, { method: 'DELETE' });
      if (res.ok) {
        showToast('Rate plan deleted successfully');
        fetchData();
      } else {
        const data = await res.json();
        showToast(data.message || 'Delete failed', 'error');
      }
    } catch (e) {
      showToast('Connection error', 'error');
    }
  }

  onMount(fetchData);
</script>

<div class="manager-content">
  <div class="page-header">
    <div>
      <h2 class="sub-title">Rate <span class="text-gradient">Plans</span></h2>
      <p class="page-subtitle">Define base pricing and default bundled services</p>
    </div>
    <button class="btn btn-primary" onclick={openCreateModal}>
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
      New Rate Plan
    </button>
  </div>

  {#if loading}
    <div class="loading-state">
      <div class="spinner"></div>
      <span>Syncing catalog...</span>
    </div>
  {:else}
    <div class="grid-table card animate-fade">
      <div class="table-header">
        <div class="col">Plan Name</div>
        <div class="col">Voice ROR</div>
        <div class="col">Data ROR</div>
        <div class="col">SMS ROR</div>
        <div class="col">Base Price</div>
        <div class="col actions">Actions</div>
      </div>
      <div class="table-body">
        {#each rateplans as plan}
          <div class="table-row">
            <div class="col name-col">
              <strong>{plan.name}</strong>
            </div>
            <div class="col font-mono">{plan.ror_voice} <small>EGP/min</small></div>
            <div class="col font-mono">{plan.ror_data} <small>EGP/MB</small></div>
            <div class="col font-mono">{plan.ror_sms} <small>EGP/msg</small></div>
            <div class="col font-mono">EGP {plan.price}</div>
            <div class="col actions">
              <button class="icon-btn edit" onclick={() => openEditModal(plan)} title="Edit">
                <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
              </button>
              <button class="icon-btn delete" onclick={() => deletePlan(plan.id)} title="Delete">
                <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>
              </button>
            </div>
          </div>
        {/each}
      </div>
    </div>
  {/if}
</div>

<Modal 
  bind:show={showModal} 
  title={isEditing ? 'Edit Rate Plan' : 'Create Rate Plan'} 
  subtitle={isEditing ? `Modifying ${currentPlan.name}` : 'Configure base rates and inclusions'}
>
  <div class="form-grid">
    <div class="form-group full">
      <label>Plan Name</label>
      <input type="text" class="input" bind:value={currentPlan.name} placeholder="e.g. Gold Unlimited" />
    </div>

    <div class="form-group">
      <label>Voice Overage Rate (EGP/min)</label>
      <input type="number" step="0.01" class="input" bind:value={currentPlan.ror_voice} />
    </div>

    <div class="form-group">
      <label>Data Overage Rate (EGP/MB)</label>
      <input type="number" step="0.01" class="input" bind:value={currentPlan.ror_data} />
    </div>

    <div class="form-group">
      <label>SMS Overage Rate (EGP/msg)</label>
      <input type="number" step="0.01" class="input" bind:value={currentPlan.ror_sms} />
    </div>

    <div class="form-group">
      <label>Monthly Subscription Price (EGP)</label>
      <input type="number" class="input" bind:value={currentPlan.price} />
    </div>

    <div class="form-group full">
      <label>Included Service Packages</label>
      <div class="packages-selection">
        {#each allPackages as pkg}
          <button 
            class="pkg-toggle-btn" 
            class:selected={currentPlan.servicePackageIds.includes(pkg.id)}
            onclick={() => togglePackage(pkg.id)}
          >
            <span class="pkg-name">{pkg.name}</span>
            <span class="pkg-meta">{pkg.amount} {pkg.type === 'data' ? 'MB' : pkg.type === 'voice' ? 'Min' : 'SMS'}</span>
            {#if currentPlan.servicePackageIds.includes(pkg.id)}
              <div class="check-overlay">✓</div>
            {/if}
          </button>
        {/each}
        {#if allPackages.length === 0}
          <div class="empty-packages">No service packages found. Create some first!</div>
        {/if}
      </div>
    </div>
  </div>

  <div class="modal-actions">
    <button class="btn btn-secondary" onclick={() => showModal = false}>Cancel</button>
    <button class="btn btn-primary" onclick={savePlan}>
      {isEditing ? 'Update Plan' : 'Create Plan'}
    </button>
  </div>
</Modal>

<style>
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .page-header { display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 2.5rem; }
  .page-subtitle { color: var(--text-muted); font-size: 1.1rem; margin-top: 0.5rem; }
  .grid-table { background: rgba(15, 15, 25, 0.4); border: 1px solid var(--border); border-radius: var(--radius-lg); overflow: hidden; }
  .table-header { display: grid; grid-template-columns: 2fr 1fr 1fr 1fr 1fr 120px; background: rgba(255, 255, 255, 0.03); padding: 1.25rem 2rem; border-bottom: 1px solid var(--border); font-weight: 700; color: var(--text-muted); text-transform: uppercase; font-size: 0.75rem; letter-spacing: 0.05em; }
  .table-row { display: grid; grid-template-columns: 2fr 1fr 1fr 1fr 1fr 120px; padding: 1.25rem 2rem; border-bottom: 1px solid rgba(255, 255, 255, 0.03); align-items: center; transition: background 0.2s; }
  .table-row:hover { background: rgba(255, 255, 255, 0.02); }
  .table-row:last-child { border-bottom: none; }
  .name-col strong { color: white; font-size: 1.1rem; }
  .font-mono { font-family: 'JetBrains Mono', monospace; color: white; font-weight: 600; }
  .font-mono small { color: var(--text-muted); font-weight: 400; font-size: 0.75rem; }
  .actions { display: flex; gap: 0.75rem; justify-content: flex-end; }
  .icon-btn { background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1); color: var(--text-muted); padding: 8px; border-radius: 8px; cursor: pointer; transition: all 0.2s; display: flex; align-items: center; justify-content: center; }
  .icon-btn:hover { color: white; background: rgba(255, 255, 255, 0.1); transform: scale(1.1); }
  .icon-btn.edit:hover { border-color: #3B82F6; color: #3B82F6; }
  .icon-btn.delete:hover { border-color: var(--red); color: var(--red); }
  .form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; margin-top: 1rem; }
  .form-group.full { grid-column: span 2; }
  .form-group label { display: block; margin-bottom: 0.5rem; font-weight: 600; font-size: 0.9rem; color: var(--text-muted); }
  .input { width: 100%; background: rgba(255, 255, 255, 0.03); border: 1px solid var(--border); border-radius: 10px; padding: 0.75rem 1rem; color: white; transition: all 0.3s; }
  .input:focus { outline: none; border-color: var(--red); background: rgba(224, 8, 0, 0.05); }
  .packages-selection { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 0.75rem; max-height: 250px; overflow-y: auto; padding: 10px; background: rgba(0,0,0,0.2); border-radius: 12px; border: 1px solid var(--border); }
  .pkg-toggle-btn { position: relative; display: flex; flex-direction: column; align-items: flex-start; text-align: left; padding: 1rem; background: rgba(255,255,255,0.03); border: 1px solid var(--border); border-radius: 10px; cursor: pointer; transition: all 0.2s; }
  .pkg-toggle-btn:hover { background: rgba(255,255,255,0.06); border-color: rgba(255,255,255,0.2); }
  .pkg-toggle-btn.selected { border-color: var(--red); background: rgba(224, 8, 0, 0.08); }
  .pkg-name { font-weight: 700; color: white; font-size: 0.9rem; margin-bottom: 0.25rem; }
  .pkg-meta { font-size: 0.75rem; color: var(--text-muted); }
  .check-overlay { position: absolute; top: 0.5rem; right: 0.5rem; width: 20px; height: 20px; background: var(--red); color: white; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 12px; font-weight: 900; }
  .modal-actions { display: flex; gap: 1rem; margin-top: 2.5rem; }
  .modal-actions button { flex: 1; }
  .loading-state { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 5rem; gap: 1rem; color: var(--text-muted); }
  .spinner { width: 40px; height: 40px; border: 3px solid rgba(224, 8, 0, 0.1); border-top-color: var(--red); border-radius: 50%; animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .empty-packages { grid-column: 1 / -1; padding: 2rem; text-align: center; color: var(--text-muted); font-style: italic; }
</style>
