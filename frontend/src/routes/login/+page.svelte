<script>
  import { base } from '$app/paths';
  import { onMount } from 'svelte';

  let username = $state('');
  let password = $state('');
  let error = $state('');
  let loading = $state(false);

  onMount(async () => {
    try {
      const res = await fetch('/api/auth/me', { credentials: 'include' });
      if (res.ok) {
        const user = await res.json();
        window.location.assign(user.role === 'admin' ? '/admin' : '/profile');
      }
    } catch {}
  });

  async function handleLogin(e) {
    e.preventDefault();
    error = '';
    loading = true;

    try {
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ username, password })
      });

      if (res.ok) {
        const user = await res.json();
        // Redirect to Profile/Admin instantly
        window.location.assign(user.role === 'admin' ? '/admin' : '/profile');
      } else {
        const data = await res.json();
        error = data.error || 'Login failed';
        loading = false;
      }
    } catch {
      error = 'Cannot connect to server';
      loading = false;
    }
  }
</script>

<svelte:head>
  <title>Login — FMRZ</title>
</svelte:head>

<div class="login-page">
  <div class="login-card card-glass animate-fade">
    <div class="login-header">
      <img src="/eand_logo.svg" alt="e&" class="login-logo" />
      <h1>Welcome back</h1>
      <p>Sign in to your account</p>
    </div>

    {#if error}
      <div class="error-msg">{error}</div>
    {/if}

    <form onsubmit={handleLogin}>
      <div class="form-group">
        <label class="label" for="username">Username</label>
        <input id="username" class="input" type="text" bind:value={username} placeholder="Enter username" required />
      </div>
      <div class="form-group">
        <label class="label" for="password">Password</label>
        <input id="password" class="input" type="password" bind:value={password} placeholder="Enter password" required />
      </div>
      <button type="submit" class="btn btn-primary" style="width: 100%;" disabled={loading}>
        {loading ? 'Signing in...' : 'Sign In'}
      </button>
    </form>

    <p class="login-footer">
      Don't have an account? <a href="/register" class="link-red">Register</a>
    </p>
  </div>
</div>

<style>
  .login-page {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 80vh;
  }
  .login-card {
    width: 100%;
    max-width: 400px;
    padding: 3rem 2.5rem;
    border-top: 3px solid var(--red);
  }
  .login-header {
    text-align: center;
    margin-bottom: 3rem;
  }
  .login-logo { height: 80px; width: auto; display: block; margin: 0 auto 1.5rem auto; }
  .login-header h1 { font-size: 1.75rem; font-weight: 800; margin-bottom: 0.5rem; letter-spacing: -0.02em; }
  .login-header p { color: var(--text-muted); font-size: 0.9375rem; }
  .error-msg {
    background: rgba(239, 68, 68, 0.1);
    border: 1px solid rgba(239, 68, 68, 0.2);
    color: #EF4444;
    padding: 1rem;
    border-radius: var(--radius-sm);
    font-size: 0.875rem;
    margin-bottom: 1.5rem;
  }
  .login-footer {
    text-align: center;
    margin-top: 1.5rem;
    font-size: 0.85rem;
    color: var(--text-muted);
  }
  .link-red { color: var(--red); font-weight: 600; }
  .link-red:hover { text-decoration: underline; }
</style>
