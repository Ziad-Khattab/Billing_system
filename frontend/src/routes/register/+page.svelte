<script>
  import { onMount } from 'svelte';

  let username = $state('');
  let password = $state('');
  let msisdn = $state('');
  let error = $state('');
  let loading = $state(false);

  onMount(async () => {
    try {
      const res = await fetch('/api/auth/me', { credentials: 'include' });
      if (res.ok) {
        const user = await res.json();
        window.location.href = user.role === 'admin' ? '/admin' : '/dashboard';
      }
    } catch {}
  });

  async function handleRegister(e) {
    e.preventDefault();
    error = '';
    loading = true;
    try {
      const res = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ username, password, msisdn })
      });
      if (res.ok) {
        window.location.href = '/dashboard';
      } else {
        const data = await res.json();
        error = data.error || 'Registration failed';
      }
    } catch { error = 'Cannot connect to server'; }
    loading = false;
  }
</script>

<svelte:head><title>Register — FMRZ</title></svelte:head>

<div class="register-page">
  <div class="register-card card-glass animate-fade">
    <div class="register-header">
      <img src="/eand_logo.svg" alt="e&" class="register-logo" />
      <h1>Join e& Billing</h1>
      <p>Enter your phone number to create an account</p>
    </div>

    {#if error}
      <div class="error-msg">{error}</div>
    {/if}

    <form onsubmit={handleRegister}>
      <div class="form-group">
        <label class="label" for="msisdn">Phone Number (MSISDN)</label>
        <input id="msisdn" class="input" type="text" bind:value={msisdn} placeholder="201000000000" required />
      </div>
      <div class="form-group">
        <label class="label" for="reg-username">Username</label>
        <input id="reg-username" class="input" type="text" bind:value={username} placeholder="choose a username" required />
      </div>
      <div class="form-group">
        <label class="label" for="reg-password">Password</label>
        <input id="reg-password" class="input" type="password" bind:value={password} placeholder="Min 6 characters" required minlength="6" />
      </div>
      <button type="submit" class="btn btn-primary" style="width: 100%;" disabled={loading}>
        {loading ? 'Verifying...' : 'Create Account'}
      </button>
    </form>

    <p class="register-footer">Already have an account? <a href="/login" class="link-red">Sign In</a></p>
  </div>
</div>

<style>
  .register-page { display: flex; align-items: center; justify-content: center; min-height: 80vh; }
  .register-card { width: 100%; max-width: 420px; padding: 2.5rem; }
  .register-header { text-align: center; margin-bottom: 2rem; }
  .register-logo { height: 180px; display: block; margin: 0 auto 0.75rem auto; }
  .register-header h1 { font-size: 1.5rem; font-weight: 700; margin-bottom: 0.25rem; }
  .register-header p { color: var(--text-muted); font-size: 0.875rem; }
  .error-msg { background: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.2); color: #EF4444; padding: 0.75rem; border-radius: var(--radius-sm); font-size: 0.85rem; margin-bottom: 1rem; }
  .register-footer { text-align: center; margin-top: 1.5rem; font-size: 0.85rem; color: var(--text-muted); }
  .link-red { color: var(--red); font-weight: 600; }
</style>
