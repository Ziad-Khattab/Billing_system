<script>
  import { onMount } from 'svelte';
  let currentSlide = $state(0);
  let loggedIn = $state(false);
  let dashboardUrl = $state('/login');

  const features = [
    { 
      icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="16" height="20" x="4" y="2" rx="2" ry="2"/><line x1="12" x2="12.01" y1="18" y2="18"/><line x1="8" x2="16" y1="6" y2="6"/><line x1="8" x2="16" y1="10" y2="10"/><line x1="8" x2="16" y1="14" y2="14"/></svg>`, 
      title: 'Smart Billing', 
      desc: 'Automated CDR processing and real-time billing calculations' 
    },
    { 
      icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" x2="12" y1="20" y2="10"/><line x1="18" x2="18" y1="20" y2="4"/><line x1="6" x2="6" y1="20" y2="16"/></svg>`, 
      title: 'Rate Plans', 
      desc: 'Flexible voice, data, and SMS rate configurations' 
    },
    { 
      icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/><line x1="16" x2="8" y1="13" y2="13"/><line x1="16" x2="8" y1="17" y2="17"/><line x1="10" x2="8" y1="9" y2="9"/></svg>`, 
      title: 'PDF Invoices', 
      desc: 'Professional invoices generated instantly' 
    },
    { 
      icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>`, 
      title: 'Secure Access', 
      desc: 'Role-based authentication for admins and customers' 
    }
  ];

  onMount(async () => {
    const res = await fetch('/api/auth/me');
    if (res.ok) {
      const user = await res.json();
      loggedIn = true;
      dashboardUrl = user.role === 'admin' ? '/admin' : '/dashboard';
    }
  });

  $effect(() => {
    const interval = setInterval(() => {
      currentSlide = (currentSlide + 1) % 3;
    }, 4000);
    return () => clearInterval(interval);
  });
</script>

<svelte:head>
  <title>FMRZ — Telecom Billing System</title>
  <meta name="description" content="FMRZ Telecom Billing Operations Platform — Manage customers, rate plans, contracts, and invoices." />
</svelte:head>

<section class="hero">
  <div class="hero-bg">
    <div class="hero-glow"></div>
    <div class="hero-grid"></div>
  </div>

  <div class="container hero-content">
    <div class="hero-text animate-fade">
      <span class="hero-badge">Telecom Billing Platform</span>
      <h1>Powering Your<br/><span class="text-gradient">Telecom Operations</span></h1>
      <p class="hero-desc">
        Complete billing management system for telecom operators.
        Customer management, CDR processing, automated billing, and invoice generation.
      </p>
      <div class="hero-actions">
        <a href="packages" class="btn btn-primary btn-lg">View Packages</a>
        {#if loggedIn}
          <a href={dashboardUrl} class="btn btn-secondary btn-lg">Go to Dashboard</a>
        {:else}
          <a href="register" class="btn btn-secondary btn-lg">Get Started</a>
        {/if}
      </div>
    </div>
    <div class="hero-visual animate-fade" style="animation-delay: 0.2s;">
      <div class="hero-card-stack">
        {#each [0, 1, 2] as i}
          <div class="hero-card" 
               class:active={currentSlide === i} 
               style="--offset: {(i - currentSlide + 3) % 3}">
            <div class="hero-card-header">
              <div class="hero-avatar">
                {#if i === 0}
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:20px;height:20px;"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                {:else if i === 1}
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:20px;height:20px;"><rect width="20" height="14" x="2" y="7" rx="2" ry="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/></svg>
                {:else}
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:20px;height:20px;"><path d="M6 4h12l4 6-10 11L2 10Z"/><path d="M2 10h20"/><path d="M6 4l6 6 6-6"/><path d="M8 10l4 11"/><path d="M16 10l-4 11"/></svg>
                {/if}
              </div>
              <div class="hero-header-lines">
                <div class="hero-card-line"></div>
                <div class="hero-card-line short"></div>
              </div>
            </div>
            <div class="hero-card-dots">
              <span class="dot" class:red={i === 0}></span>
              <span class="dot" class:red={i === 1}></span>
              <span class="dot" class:red={i === 2}></span>
            </div>
          </div>
        {/each}
      </div>
    </div>
  </div>
</section>

<section class="features container">
  <h2 class="section-title">Built for <span class="text-gradient">Performance</span></h2>
  <div class="grid-4">
    {#each features as feature, i}
      <div class="card feature-card animate-fade" style="animation-delay: {i * 0.1}s">
        <span class="feature-icon">{@html feature.icon}</span>
        <h3>{feature.title}</h3>
        <p>{feature.desc}</p>
      </div>
    {/each}
  </div>
</section>

<section class="cta-section">
  <div class="container">
    <div class="cta-card card-glass">
      <h2>Ready to get started?</h2>
      <p>Browse our packages or register for your own billing dashboard.</p>
      <div class="cta-actions">
        <a href="packages" class="btn btn-primary">Browse Packages</a>
        {#if loggedIn}
          <a href={dashboardUrl} class="btn btn-secondary">Go to Dashboard</a>
        {:else}
          <a href="login" class="btn btn-secondary">Login</a>
        {/if}
      </div>
    </div>
  </div>
</section>

<style>
  .hero {
    position: relative;
    min-height: 85vh;
    display: flex;
    align-items: center;
    overflow: hidden;
  }
  .hero-bg {
    position: absolute;
    inset: 0;
    z-index: 0;
  }
  .hero-glow {
    position: absolute;
    top: -40%;
    right: -20%;
    width: 800px;
    height: 800px;
    background: radial-gradient(circle, rgba(224,8,0,0.3) 0%, transparent 70%);
    border-radius: 50%;
    animation: pulse-glow 6s ease infinite;
  }
  .hero-grid {
    position: absolute;
    inset: 0;
    background-image:
      linear-gradient(rgba(255,255,255,0.02) 1px, transparent 1px),
      linear-gradient(90deg, rgba(255,255,255,0.02) 1px, transparent 1px);
    background-size: 60px 60px;
  }
  .hero-content {
    position: relative;
    z-index: 1;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 4rem;
    align-items: center;
  }
  .hero-badge {
    display: inline-block;
    padding: 0.375rem 1rem;
    background: rgba(224, 8, 0, 0.1);
    border: 1px solid rgba(224, 8, 0, 0.2);
    border-radius: 100px;
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--red);
    margin-bottom: 1.5rem;
  }
  .hero-text h1 {
    font-size: 3.5rem;
    font-weight: 800;
    line-height: 1.1;
    margin-bottom: 1.5rem;
  }
  .text-gradient {
    background: linear-gradient(135deg, var(--red), var(--red-light), #FF6B6B);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }
  .hero-desc {
    font-size: 1.1rem;
    color: var(--text-secondary);
    max-width: 500px;
    margin-bottom: 2rem;
  }
  .hero-actions { display: flex; gap: 1rem; }
  .btn-lg { padding: 1rem 2rem; font-size: 1rem; }

  .hero-card-stack {
    position: relative;
    width: 100%;
    height: 300px;
    perspective: 1000px;
  }
  .hero-card {
    position: absolute;
    width: 300px;
    height: 180px;
    background: rgba(15, 15, 21, 0.8);
    backdrop-filter: blur(20px);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: var(--radius);
    padding: 1.5rem;
    transition: all 0.8s cubic-bezier(0.16, 1, 0.3, 1);
    opacity: calc(1 - var(--offset) * 0.35);
    transform: 
      translateX(calc(var(--offset) * -50px)) 
      translateY(calc(var(--offset) * -35px)) 
      scale(calc(1 - var(--offset) * 0.12));
    z-index: calc(10 - var(--offset));
  }
  .hero-card.active {
    opacity: 1;
    background: rgba(20, 20, 28, 0.9);
    border-color: rgba(224, 8, 0, 0.5);
    box-shadow: 0 20px 50px rgba(0, 0, 0, 0.8), 0 0 30px rgba(224, 8, 0, 0.15);
    transform: translateX(0) translateY(0) scale(1.1);
    z-index: 20;
  }
  .hero-card-header {
    display: flex;
    gap: 1rem;
    align-items: center;
    margin-bottom: 1.5rem;
  }
  .hero-avatar {
    width: 44px;
    height: 44px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--red);
  }
  .hero-header-lines { flex: 1; }
  .hero-card-line {
    height: 8px;
    background: linear-gradient(90deg, var(--red), transparent);
    border-radius: 4px;
    margin-bottom: 0.75rem;
    width: 80%;
  }
  .hero-card-line.short { width: 50%; background: var(--border); }
  .hero-card-dots {
    display: flex;
    gap: 8px;
    position: absolute;
    bottom: 1.5rem;
    left: 1.5rem;
  }
  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--border);
  }
  .dot.red { background: var(--red); }

  .features {
    padding: 5rem 0;
  }
  .section-title {
    text-align: center;
    font-size: 2rem;
    font-weight: 700;
    margin-bottom: 3rem;
  }
  .feature-card {
    text-align: center;
    padding: 2rem 1.5rem;
  }
  .feature-icon {
    display: flex;
    justify-content: center;
    margin-bottom: 1.5rem;
    color: var(--red);
  }
  .feature-icon :global(svg) {
    width: 48px;
    height: 48px;
    filter: drop-shadow(0 0 12px rgba(224, 8, 0, 0.4));
  }
  .feature-card h3 {
    font-size: 1.1rem;
    font-weight: 600;
    margin-bottom: 0.5rem;
  }
  .feature-card p {
    font-size: 0.85rem;
    color: var(--text-muted);
    line-height: 1.5;
  }

  .cta-section {
    padding: 3rem 0 5rem;
  }
  .cta-card {
    text-align: center;
    padding: 3rem;
    background: linear-gradient(135deg, var(--bg-card), rgba(224, 8, 0, 0.05));
  }
  .cta-card h2 { font-size: 1.75rem; margin-bottom: 0.75rem; }
  .cta-card p { color: var(--text-secondary); margin-bottom: 1.5rem; }
  .cta-actions { display: flex; gap: 1rem; justify-content: center; }

  @media (max-width: 768px) {
    .hero-content { grid-template-columns: 1fr; }
    .hero-text h1 { font-size: 2.25rem; }
    .hero-visual { display: none; }
  }
</style>
