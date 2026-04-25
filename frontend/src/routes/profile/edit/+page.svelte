<script>
  import { base } from '$app/paths';
  import { onMount } from 'svelte';
  
  let profile = $state({ name: '', address: '', email: '' });
  let loading = $state(true);
  let saving = $state(false);
  let message = $state('');

  async function loadProfile() {
    const res = await fetch('/api/customer/profile', { credentials: 'include' });
    if (res.ok) {
      profile = await res.json();
    }
    loading = false;
  }

  async function save() {
    saving = true;
    message = '';
    const res = await fetch('/api/customer/profile', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(profile),
      credentials: 'include'
    });
    if (res.ok) {
      message = 'Profile updated successfully! ✅';
      setTimeout(() => message = '', 3000);
    } else {
      message = 'Failed to update profile. ❌';
    }
    saving = false;
  }

  onMount(async () => {
    try {
      const res = await fetch('/api/auth/me', { credentials: 'include' });
      if (!res.ok) {
        window.location.href = '/login';
        return;
      }
      await loadProfile();
    } catch {
      window.location.href = '/login';
    }
  });
</script>

<svelte:head><title>Edit Profile — FMRZ</title></svelte:head>

<div class="container narrow animate-fade">
  <div class="page-header">
    <a href="/profile" class="back-link">← Back to Profile</a>
    <h1>Edit <span class="text-gradient">Profile</span></h1>
  </div>

  {#if loading}
    <div class="loading">Loading profile...</div>
  {:else}
    <div class="card form-card">
      <form onsubmit={(e) => { e.preventDefault(); save(); }}>
        <div class="form-group">
          <label for="name">Full Name</label>
          <input type="text" id="name" bind:value={profile.name} required />
        </div>

        <div class="form-group">
          <label for="email">Email Address</label>
          <input type="email" id="email" bind:value={profile.email} placeholder="Enter your email" />
          <p class="help-text">We'll use this to send your monthly invoices.</p>
        </div>

        <div class="form-group">
          <label for="address">Mailing Address</label>
          <textarea id="address" bind:value={profile.address} rows="3"></textarea>
        </div>

        <div class="form-actions">
          <button type="submit" class="btn btn-primary" disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
          {#if message}
            <span class="status-msg">{message}</span>
          {/if}
        </div>
      </form>
    </div>
  {/if}
</div>

<style>
  .narrow { max-width: 600px; margin: 0 auto; }
  .back-link { display: block; margin-bottom: 1rem; color: var(--text-muted); font-size: 0.9rem; text-decoration: none; }
  .back-link:hover { color: var(--red); }
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  
  .form-card { padding: 2.5rem; }
  .form-group { margin-bottom: 1.5rem; }
  .form-group label { display: block; margin-bottom: 0.5rem; font-weight: 600; color: var(--text-secondary); }
  .form-group input, .form-group textarea {
    width: 100%;
    padding: 0.75rem 1rem;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    color: white;
    font-size: 1rem;
    transition: all 0.2s;
  }
  .form-group input:focus, .form-group textarea:focus {
    outline: none;
    border-color: var(--red);
    box-shadow: 0 0 0 2px rgba(224, 8, 0, 0.2);
  }
  .help-text { font-size: 0.8rem; color: var(--text-muted); margin-top: 0.5rem; }
  
  .form-actions { display: flex; align-items: center; gap: 1.5rem; margin-top: 2rem; }
  .status-msg { font-size: 0.9rem; font-weight: 600; animation: fade-in 0.3s ease; }
  
  .loading { text-align: center; padding: 4rem; color: var(--text-muted); }

  @keyframes fade-in { from { opacity: 0; transform: translateX(-10px); } to { opacity: 1; transform: translateX(0); } }
</style>
