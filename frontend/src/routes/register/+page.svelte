<script>
  import { onMount } from 'svelte';

  let username  = $state('');
  let password  = $state('');
  let name      = $state('');
  let email     = $state('');
  let address   = $state('');
  let birthdate = $state('');
  let error     = $state('');
  let loading   = $state(false);
  let planId    = $state(null);

  onMount(async () => {
    // Capture plan from URL
    const params = new URLSearchParams(window.location.search);
    planId = params.get('plan');

    try {
      const res = await fetch('/api/auth/me', { credentials: 'include' });
      if (res.ok) {
        const user = await res.json();
        window.location.assign(user.role === 'admin' ? '/admin' : '/profile');
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
        body: JSON.stringify({ username, password, name, email, address, birthdate })
      });
      if (res.ok) {
        // Forward with plan persistence
        const target = planId ? `/onboarding?plan=${planId}` : '/onboarding';
        window.location.assign(target);
      } else {
        const data = await res.json();
        error = data.error || 'Registration failed';
        loading = false;
      }
    } catch {
      error = 'Cannot connect to server';
      loading = false;
    }
  }
</script>

<svelte:head><title>Join FMRZ — Registration</title></svelte:head>

<div class="register-page">
  <div class="register-card card animate-fade">
    <div class="register-header">
      <img src="/red-logo.png" alt="FMRZ" class="register-logo" />
      <h1>Join us 
        <span class="heart-pulse">
          <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg>
        </span>
      </h1>
      <p>Create your premium account to get started</p>
    </div>

    {#if error}
      <div class="error-msg animate-fade">{error}</div>
    {/if}

    <form onsubmit={handleRegister} class="register-form">
      <div class="grid-2" style="gap: 1rem; margin-bottom: 1rem;">
        <div class="form-group">
          <label class="label" for="reg-name">Full Name</label>
          <input id="reg-name" class="input" type="text"
                 bind:value={name} placeholder="e.g. Ahmed Ali" required />
        </div>
        <div class="form-group">
          <label class="label" for="reg-username">Username</label>
          <input id="reg-username" class="input" type="text"
                 bind:value={username} placeholder="User123" required />
        </div>
      </div>

      <div class="form-group">
        <label class="label" for="reg-email">Email Address</label>
        <input id="reg-email" class="input" type="email"
               bind:value={email} placeholder="ahmed@email.com" required />
      </div>

      <div class="form-group">
        <label class="label" for="reg-password">Security Password</label>
        <input id="reg-password" class="input" type="password"
               bind:value={password} placeholder="••••••••"
               required minlength="6" />
      </div>

      <div class="grid-2" style="gap: 1rem; margin-bottom: 1rem;">
        <div class="form-group">
          <label class="label" for="reg-address">City / Address</label>
          <input id="reg-address" class="input" type="text"
                 bind:value={address} placeholder="Cairo, Egypt" />
        </div>
        <div class="form-group">
          <label class="label" for="reg-birthdate">Date of Birth</label>
          <input id="reg-birthdate" class="input" type="date"
                 bind:value={birthdate} />
        </div>
      </div>

      <button type="submit" class="btn btn-primary"
              style="width: 100%; margin-top: 1rem; height: 50px; font-size: 1.1rem;"
              disabled={loading}>
        {loading ? 'Finalizing Profile...' : 'Create FMRZ Account'}
      </button>
    </form>

    <div class="register-footer">
      <p>Already a member? <a href="/login" class="link-red">Sign In</a></p>
    </div>
  </div>
</div>

<style>
  .register-page { 
    display: flex; 
    align-items: center; 
    justify-content: center; 
    min-height: 85vh;
    padding: 2rem;
  }
  .register-card { 
    width: 100%; 
    max-width: 520px; 
    padding: 3rem;
    background: rgba(10, 10, 15, 0.9) !important;
    backdrop-filter: blur(20px) !important;
    border: 1px solid rgba(255, 255, 255, 0.08) !important;
    box-shadow: 0 40px 100px rgba(0,0,0,0.6) !important;
  }
  .register-header { text-align: center; margin-bottom: 2.5rem; }
  .register-logo { height: 120px; width: auto; display: block; margin: 0 auto 1.5rem auto; filter: drop-shadow(0 0 10px rgba(255,255,255,0.1)); }
  .register-header h1 { font-size: 1.75rem; font-weight: 800; margin-bottom: 0.5rem; letter-spacing: -0.02em; }
  .register-header p { color: var(--text-muted); font-size: 0.95rem; }
  
  .register-form { margin-top: 1rem; }
  
  .register-footer { 
    text-align: center; 
    margin-top: 2rem; 
    padding-top: 1.5rem;
    border-top: 1px solid rgba(255,255,255,0.05);
    font-size: 0.9rem; 
    color: var(--text-muted); 
  }
  
  .link-red { 
    color: var(--red-light); 
    font-weight: 700; 
    text-decoration: none;
    margin-left: 0.5rem;
  }
  .link-red:hover { text-decoration: underline; }

  .heart-pulse {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: var(--red-light);
    animation: heart-beat 1.5s infinite;
    margin-left: 0.5rem;
    vertical-align: middle;
    filter: drop-shadow(0 0 8px rgba(224, 8, 0, 0.4));
  }

  @keyframes heart-beat {
    0%, 100% { transform: scale(1); }
    50% { transform: scale(1.2); }
  }

  @media (max-width: 600px) {
    .register-card { padding: 2rem 1.5rem; }
    .grid-2 { grid-template-columns: 1fr; }
  }
</style>