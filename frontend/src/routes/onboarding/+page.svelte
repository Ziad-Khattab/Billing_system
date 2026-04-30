<script>
    import { onMount } from 'svelte';

    let step       = $state(1); // 1 = pick number, 2 = pick plan, 3 = done
    let msisdns    = $state([]);
    let rateplans  = $state([]);
    let selected   = $state({ msisdn: '', ratePlanId: null });
    let loading    = $state(false);
    let error      = $state('');
    let planFromUrl = $state(null);

    onMount(async () => {
        // Capture plan from URL
        const params = new URLSearchParams(window.location.search);
        planFromUrl = params.get('plan');
        if (planFromUrl) selected.ratePlanId = parseInt(planFromUrl);

        try {
            const [m, r] = await Promise.all([
                fetch('/api/customer/onboarding/msisdns', { credentials: 'include' }).then(res => res.json()),
                fetch('/api/customer/onboarding/rateplans', { credentials: 'include' }).then(res => res.json())
            ]);
            msisdns   = m;
            rateplans = r;
        } catch (e) {
            error = "Failed to load activation data.";
        }
    });

    async function activate() {
        loading = true;
        error   = '';
        try {
            const res = await fetch('/api/customer/onboarding/activate', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify({
                    msisdn:     selected.msisdn,
                    ratePlanId: selected.ratePlanId
                })
            });
            const data = await res.json();
            if (!res.ok) { error = data.error || 'Activation failed'; return; }
            step = 3;
        } catch {
            error = 'Cannot connect to server';
        } finally {
            loading = false;
        }
    }
</script>

<svelte:head><title>Activate My Line — FMRZ</title></svelte:head>

<div class="onboarding-page">
    <div class="onboarding-card card animate-fade">
        <div class="logo-header">
            <img src="/red-logo.png" alt="FMRZ" class="fmrz-logo-small" />
            <div class="header-text">
                <h1>Service Activation</h1>
                <p>Follow the steps to go live on the network</p>
            </div>
        </div>

        <!-- Progress indicator -->
        <div class="steps">
            <div class="step" class:active={step >= 1} class:done={step > 1}>
                <span class="step-num">{step > 1 ? '✓' : '1'}</span>
                <span class="step-lbl">Number</span>
            </div>
            <div class="step-line" class:done={step > 1}></div>
            <div class="step" class:active={step >= 2} class:done={step > 2}>
                <span class="step-num">{step > 2 ? '✓' : '2'}</span>
                <span class="step-lbl">Plan</span>
            </div>
            <div class="step-line" class:done={step > 2}></div>
            <div class="step" class:active={step >= 3}>
                <span class="step-num">3</span>
                <span class="step-lbl">Done</span>
            </div>
        </div>

        {#if error}
            <div class="error-msg animate-fade">{error}</div>
        {/if}

        <!-- STEP 1: Pick MSISDN -->
        {#if step === 1}
            <div class="step-content animate-fade">
                <h2>Choose your new number</h2>
                <p class="subtitle">Pick a unique phone number from our available pool</p>
                <div class="number-grid">
                    {#each msisdns as m}
                        <button
                                class="number-btn"
                                class:selected={selected.msisdn === m.msisdn}
                                onclick={() => selected.msisdn = m.msisdn}
                        >
                            <span class="prefix">010</span>
                            <span class="main-num">{m.msisdn.substring(3)}</span>
                        </button>
                    {/each}
                </div>
                <button class="btn btn-primary full-width"
                        disabled={!selected.msisdn}
                        onclick={() => step = 2}
                        style="height: 50px; font-size: 1rem;">
                    Continue to Plan Selection →
                </button>
            </div>

            <!-- STEP 2: Pick Rateplan -->
        {:else if step === 2}
            <div class="step-content animate-fade">
                <h2>Confirm your Rate Plan</h2>
                <p class="subtitle">Selected number: <span class="highlight">{selected.msisdn}</span></p>
                <div class="plan-list">
                    {#each rateplans as plan}
                        <button
                                class="plan-card-premium"
                                class:selected={selected.ratePlanId === plan.id}
                                onclick={() => selected.ratePlanId = plan.id}
                        >
                            <div class="plan-info">
                                <div class="plan-name">{plan.name}</div>
                                <div class="plan-specs">
                                    <span>Voice: {plan.ror_voice}/min</span>
                                    <span class="dot">•</span>
                                    <span>Data: {plan.ror_data}/MB</span>
                                </div>
                            </div>
                            <div class="plan-price-box">
                                <span class="currency">EGP</span>
                                <span class="amount">{plan.price}</span>
                                <span class="period">/mo</span>
                            </div>
                        </button>
                    {/each}
                </div>
                <div class="btn-row">
                    <button class="btn btn-secondary" onclick={() => step = 1}>← Change Number</button>
                    <button class="btn btn-primary"
                            disabled={!selected.ratePlanId || loading}
                            onclick={activate}
                            style="min-width: 160px;">
                        {loading ? 'Activating...' : 'Confirm & Activate'}
                    </button>
                </div>
            </div>

            <!-- STEP 3: Success -->
        {:else if step === 3}
            <div class="success-screen animate-fade">
                <div class="success-glow"></div>
                <div class="success-icon-box">
                    <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>
                </div>
                <h2>Activation Successful!</h2>
                <p>Your premium line <strong>{selected.msisdn}</strong> is now live on the FMRZ network.</p>
                <div class="success-actions">
                    <a href="/profile" class="btn btn-primary full-width" style="height: 50px;">Go to My Dashboard</a>
                </div>
            </div>
        {/if}

    </div>
</div>

<style>
    .onboarding-page { display: flex; align-items: center; justify-content: center; min-height: 90vh; padding: 2rem; }
    .onboarding-card { 
        width: 100%; 
        max-width: 600px; 
        padding: 3rem;
        background: rgba(10, 10, 15, 0.9) !important;
        backdrop-filter: blur(20px) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
    }

    .logo-header { display: flex; align-items: center; gap: 1.5rem; margin-bottom: 2.5rem; }
    .fmrz-logo-small { height: 44px; width: auto; opacity: 1; filter: drop-shadow(0 0 8px rgba(255,255,255,0.1)); }
    .header-text h1 { font-size: 1.5rem; font-weight: 800; margin: 0; letter-spacing: -0.02em; }
    .header-text p { font-size: 0.9rem; color: var(--text-muted); margin: 0; }

    /* Modern Stepper */
    .steps { display: flex; align-items: center; justify-content: space-between; margin-bottom: 3rem; position: relative; }
    .step { display: flex; flex-direction: column; align-items: center; gap: 0.5rem; z-index: 2; }
    .step-num { 
        width: 32px; height: 32px; border-radius: 50%; background: rgba(255,255,255,0.05); 
        display: flex; align-items: center; justify-content: center; font-size: 0.85rem; font-weight: 700;
        border: 1px solid rgba(255,255,255,0.1); transition: all 0.3s; color: var(--text-muted);
    }
    .step-lbl { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-muted); }
    .step.active .step-num { background: var(--red); color: white; border-color: var(--red); box-shadow: 0 0 15px rgba(224, 8, 0, 0.3); }
    .step.active .step-lbl { color: white; }
    .step.done .step-num { background: #22C55E; color: white; border-color: #22C55E; }
    
    .step-line { flex: 1; height: 2px; background: rgba(255,255,255,0.05); margin-top: -1.2rem; margin-left: 0.5rem; margin-right: 0.5rem; }
    .step-line.done { background: #22C55E; opacity: 0.5; }

    .step-content h2 { font-size: 1.25rem; font-weight: 700; margin-bottom: 0.5rem; }
    .subtitle { color: var(--text-muted); font-size: 0.9rem; margin-bottom: 1.5rem; }
    .highlight { color: var(--red-light); font-weight: 700; }

    /* Number Grid Refinement */
    .number-grid { 
        display: grid; grid-template-columns: repeat(2, 1fr); gap: 1rem; margin-bottom: 2rem; 
        max-height: 240px; overflow-y: auto; padding-right: 5px;
    }
    .number-btn { 
        padding: 1.25rem; border: 1px solid rgba(255,255,255,0.05); border-radius: 16px;
        background: rgba(255,255,255,0.02); cursor: pointer; transition: all 0.2s;
        display: flex; align-items: center; justify-content: center; gap: 0.25rem;
    }
    .number-btn:hover { background: rgba(255,255,255,0.05); border-color: var(--red); }
    .number-btn.selected { background: rgba(224, 8, 0, 0.1); border-color: var(--red); transform: scale(1.02); }
    .number-btn .prefix { color: var(--text-muted); font-size: 0.9rem; }
    .number-btn .main-num { font-weight: 800; font-size: 1.1rem; letter-spacing: 0.05em; font-family: 'JetBrains Mono', monospace; }

    /* Plan List Refinement */
    .plan-list { display: flex; flex-direction: column; gap: 1rem; margin-bottom: 2rem; }
    .plan-card-premium { 
        display: flex; justify-content: space-between; align-items: center; padding: 1.25rem 1.5rem;
        border: 1px solid rgba(255,255,255,0.05); border-radius: 16px; background: rgba(255,255,255,0.02);
        cursor: pointer; transition: all 0.2s; text-align: left;
    }
    .plan-card-premium:hover { background: rgba(255,255,255,0.05); border-color: var(--red); }
    .plan-card-premium.selected { background: rgba(224, 8, 0, 0.1); border-color: var(--red); }
    
    .plan-name { font-weight: 800; font-size: 1.1rem; margin-bottom: 0.25rem; }
    .plan-specs { font-size: 0.8rem; color: var(--text-muted); display: flex; align-items: center; gap: 0.5rem; }
    .dot { opacity: 0.3; }

    .plan-price-box { display: flex; align-items: baseline; gap: 2px; }
    .plan-price-box .currency { font-size: 0.7rem; font-weight: 700; color: var(--text-muted); }
    .plan-price-box .amount { font-size: 1.5rem; font-weight: 900; color: var(--red-light); }
    .plan-price-box .period { font-size: 0.75rem; color: var(--text-muted); }

    .btn-row { display: flex; gap: 1rem; justify-content: space-between; }
    .full-width { width: 100%; }

    /* Success Screen */
    .success-screen { text-align: center; padding: 2rem 0; position: relative; }
    .success-icon-box { 
        width: 80px; height: 80px; background: #22C55E; border-radius: 50%; margin: 0 auto 1.5rem auto;
        display: flex; align-items: center; justify-content: center; color: white;
        box-shadow: 0 0 30px rgba(34, 197, 94, 0.4);
    }
    .success-screen h2 { font-size: 1.75rem; font-weight: 900; margin-bottom: 1rem; }
    .success-screen p { color: var(--text-muted); line-height: 1.6; margin-bottom: 2.5rem; }
    .success-glow { 
        position: absolute; top: 0; left: 50%; transform: translateX(-50%);
        width: 200px; height: 200px; background: radial-gradient(circle, rgba(34, 197, 94, 0.15) 0%, transparent 70%);
        z-index: -1;
    }

    .error-msg { 
        background: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.2);
        color: #EF4444; padding: 1rem; border-radius: 12px; font-size: 0.9rem; margin-bottom: 2rem; 
    }
</style>
