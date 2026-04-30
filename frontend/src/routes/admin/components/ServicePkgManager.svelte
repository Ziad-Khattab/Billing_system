<script>
  import { onMount } from 'svelte';
  import { fade, fly } from 'svelte/transition';
  import { showToast } from '$lib/toast.svelte.js';
  import Modal from '$lib/components/Modal.svelte';

  let packages = $state([]);
  let loading = $state(true);
  let showModal = $state(false);
  let isEditing = $state(false);
  let currentPkg = $state({
    name: '',
    type: 'voice',
    amount: 0,
    priority: 10,
    price: 0,
    description: '',
    is_roaming: false
  });

  async function fetchPackages() {
    loading = true;
    try {
      const res = await fetch('/api/admin/service-packages');
      if (res.ok) {
        packages = await res.json();
      }
    } catch (e) {
      showToast('Failed to fetch packages', 'error');
    } finally {
      loading = false;
    }
  }

  function openCreateModal() {
    isEditing = false;
    currentPkg = {
      name: '',
      type: 'voice',
      amount: 0,
      priority: 10,
      price: 0,
      description: '',
      is_roaming: false
    };
    showModal = true;
  }

  function openEditModal(pkg) {
    isEditing = true;
    currentPkg = { ...pkg };
    showModal = true;
  }

  async function savePackage() {
    const url = isEditing ? `/api/admin/service-packages/${currentPkg.id}` : '/api/admin/service-packages';
    const method = isEditing ? 'PUT' : 'POST';
    try {
      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(currentPkg)
      });
      if (res.ok) {
        showToast(`Package ${isEditing ? 'updated' : 'created'} successfully`);
        showModal = false;
        fetchPackages();
      } else {
        const data = await res.json();
        showToast(data.message || 'Action failed', 'error');
      }
    } catch (e) {
      showToast('Connection error', 'error');
    }
  }

  async function deletePackage(id) {
    if (!confirm('Are you sure you want to delete this package?')) return;
    try {
      const res = await fetch(`/api/admin/service-packages/${id}`, { method: 'DELETE' });
      if (res.ok) {
        showToast('Package deleted successfully');
        fetchPackages();
      } else {
        const data = await res.json();
        showToast(data.message || 'Delete failed', 'error');
      }
    } catch (e) {
      showToast('Connection error', 'error');
    }
  }

  onMount(fetchPackages);
</script>

<div class="manager-content">
  <div class="page-header">
    <div>
      <h2 class="sub-title">Service <span class="text-gradient">Packages</span></h2>
      <p class="page-subtitle">Configure bundle quotas and priority</p>
    </div>
    <button class="btn btn-primary" onclick={openCreateModal}>
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
      New Package
    </button>
  </div>

  {#if loading}
    <div class="loading-state">
      <div class="spinner"></div>
      <span>Loading packages...</span>
    </div>
  {:else}
    <div class="grid-table card animate-fade">
      <div class="table-header">
        <div class="col">Name</div>
        <div class="col">Type</div>
        <div class="col">Amount</div>
        <div class="col">Price</div>
        <div class="col">Priority</div>
        <div class="col">Roaming</div>
        <div class="col actions">Actions</div>
      </div>
      <div class="table-body">
        {#each packages as pkg}
          <div class="table-row">
            <div class="col name-col">
              <strong>{pkg.name}</strong>
              <small>{pkg.description || 'No description'}</small>
            </div>
            <div class="col">
              <span class="badge badge-{pkg.type}">{pkg.type}</span>
            </div>
            <div class="col font-mono">{pkg.amount}</div>
            <div class="col font-mono">EGP {pkg.price}</div>
            <div class="col">{pkg.priority}</div>
            <div class="col">
              <span class="roaming-status {pkg.is_roaming ? 'is-roaming' : ''}">
                {pkg.is_roaming ? 'Yes' : 'No'}
              </span>
            </div>
            <div class="col actions">
              <button class="icon-btn edit" onclick={() => openEditModal(pkg)} title="Edit">
                <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
              </button>
              <button class="icon-btn delete" onclick={() => deletePackage(pkg.id)} title="Delete">
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
  title={isEditing ? 'Edit Package' : 'Create Package'} 
  subtitle={isEditing ? `Modifying ${currentPkg.name}` : 'Define new quota bundle'}
>
  <div class="form-grid">
    <div class="form-group full">
      <label>Package Name</label>
      <input type="text" class="input" bind:value={currentPkg.name} placeholder="e.g. Summer Data Boost" />
    </div>

    <div class="form-group">
      <label>Service Type</label>
      <select class="input" bind:value={currentPkg.type}>
        <option value="voice">Voice</option>
        <option value="data">Data</option>
        <option value="sms">SMS</option>
      </select>
    </div>

    <div class="form-group">
      <label>Amount (MB/Min/Count)</label>
      <input type="number" class="input" bind:value={currentPkg.amount} />
    </div>

    <div class="form-group">
      <label>Price (EGP)</label>
      <input type="number" class="input" bind:value={currentPkg.price} />
    </div>

    <div class="form-group">
      <label>Priority (Lower = First)</label>
      <input type="number" class="input" bind:value={currentPkg.priority} />
    </div>

    <div class="form-group full">
      <label>Description</label>
      <textarea class="input" rows="3" bind:value={currentPkg.description} placeholder="Describe what's in the package..."></textarea>
    </div>

    <div class="form-group full checkbox-group">
      <label class="checkbox-container">
        <input type="checkbox" bind:checked={currentPkg.is_roaming} />
        <span class="checkmark"></span>
        Enable for Roaming Usage
      </label>
    </div>
  </div>

  <div class="modal-actions">
    <button class="btn btn-secondary" onclick={() => showModal = false}>Cancel</button>
    <button class="btn btn-primary" onclick={savePackage}>
      {isEditing ? 'Update Package' : 'Create Package'}
    </button>
  </div>
</Modal>

<style>
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .page-header { display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 2.5rem; }
  .page-subtitle { color: var(--text-muted); font-size: 1.1rem; margin-top: 0.5rem; }
  .grid-table { background: rgba(15, 15, 25, 0.4); border: 1px solid var(--border); border-radius: var(--radius-lg); overflow: hidden; }
  .table-header { display: grid; grid-template-columns: 2fr 1fr 1fr 1fr 0.8fr 0.8fr 120px; background: rgba(255, 255, 255, 0.03); padding: 1.25rem 2rem; border-bottom: 1px solid var(--border); font-weight: 700; color: var(--text-muted); text-transform: uppercase; font-size: 0.75rem; letter-spacing: 0.05em; }
  .table-row { display: grid; grid-template-columns: 2fr 1fr 1fr 1fr 0.8fr 0.8fr 120px; padding: 1.25rem 2rem; border-bottom: 1px solid rgba(255, 255, 255, 0.03); align-items: center; transition: background 0.2s; }
  .table-row:hover { background: rgba(255, 255, 255, 0.02); }
  .table-row:last-child { border-bottom: none; }
  .name-col { display: flex; flex-direction: column; gap: 0.25rem; }
  .name-col strong { color: white; font-size: 1.05rem; }
  .name-col small { color: var(--text-muted); font-size: 0.85rem; }
  .badge { padding: 4px 10px; border-radius: 6px; font-size: 0.75rem; font-weight: 700; text-transform: uppercase; border: 1px solid transparent; }
  .badge-voice { background: rgba(59, 130, 246, 0.1); color: #60a5fa; border-color: rgba(59, 130, 246, 0.2); }
  .badge-data { background: rgba(16, 185, 129, 0.1); color: #34d399; border-color: rgba(16, 185, 129, 0.2); }
  .badge-sms { background: rgba(139, 92, 246, 0.1); color: #a78bfa; border-color: rgba(139, 92, 246, 0.2); }
  .roaming-status { font-size: 0.85rem; color: var(--text-muted); }
  .roaming-status.is-roaming { color: #F59E0B; font-weight: 700; }
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
  .checkbox-group { display: flex; align-items: center; margin-top: 0.5rem; }
  .checkbox-container { display: flex; align-items: center; gap: 10px; cursor: pointer; user-select: none; font-weight: 600; color: white; }
  .checkbox-container input { display: none; }
  .checkmark { width: 20px; height: 20px; border: 2px solid var(--border); border-radius: 6px; display: flex; align-items: center; justify-content: center; transition: all 0.2s; }
  .checkbox-container input:checked + .checkmark { background: var(--red); border-color: var(--red); }
  .checkbox-container input:checked + .checkmark::after { content: '✓'; color: white; font-size: 14px; font-weight: 900; }
  .modal-actions { display: flex; gap: 1rem; margin-top: 2.5rem; }
  .modal-actions button { flex: 1; }
  .loading-state { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 5rem; gap: 1rem; color: var(--text-muted); }
  .spinner { width: 40px; height: 40px; border: 3px solid rgba(224, 8, 0, 0.1); border-top-color: var(--red); border-radius: 50%; animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
