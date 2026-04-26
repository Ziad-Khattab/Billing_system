<script>
    import { onMount } from 'svelte';

    let step       = $state(1); // 1 = pick number, 2 = pick plan, 3 = done
    let msisdns    = $state([]);
    let rateplans  = $state([]);
    let selected   = $state({ msisdn: '', ratePlanId: null });
    let loading    = $state(false);
    let error      = $state('');

    onMount(async () => {
        const [m, r] = await Promise.all([
            fetch('/api/customer/onboarding/msisdns', { credentials: 'include' }).then(r => r.json()),
            fetch('/api/customer/onboarding/rateplans', { credentials: 'include' }).then(r => r.json())
        ]);
        msisdns   = m;
        rateplans = r;
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

<svelte:head><title>Activate — FMRZ</title></svelte:head>

<div class="onboarding-page">
    <div class="onboarding-card card-glass animate-fade">

        <!-- Progress indicator -->
        <div class="steps">
            <div class="step" class:active={step >= 1} class:done={step > 1}>1. Choose Number</div>
            <div class="step-divider">→</div>
            <div class="step" class:active={step >= 2} class:done={step > 2}>2. Choose Plan</div>
            <div class="step-divider">→</div>
            <div class="step" class:active={step >= 3}>3. Done</div>
        </div>

        {#if error}
            <div class="error-msg">{error}</div>
        {/if}

        <!-- STEP 1: Pick MSISDN -->
        {#if step === 1}
            <h2>Choose your number</h2>
            <p class="subtitle">Pick a phone number from the available list</p>
            <div class="number-grid">
                {#each msisdns as m}
                    <button
                            class="number-btn"
                            class:selected={selected.msisdn === m.msisdn}
                            onclick={() => selected.msisdn = m.msisdn}
                    >
                        {m.msisdn}
                    </button>
                {/each}
            </div>
            <button class="btn btn-primary full-width"
                    disabled={!selected.msisdn}
                    onclick={() => step = 2}>
                Continue →
            </button>

            <!-- STEP 2: Pick Rateplan -->
        {:else if step === 2}
            <h2>Choose your plan</h2>
            <p class="subtitle">Selected number: <strong>{selected.msisdn}</strong></p>
            <div class="plan-list">
                {#each rateplans as plan}
                    <button
                            class="plan-card"
                            class:selected={selected.ratePlanId === plan.id}
                            onclick={() => selected.ratePlanId = plan.id}
                    >
                        <div class="plan-name">{plan.name}</div>
                        <div class="plan-price">EGP {plan.price} / month</div>
                        <div class="plan-details">
                            Voice: {plan.ror_voice} / min &nbsp;|&nbsp;
                            Data: {plan.ror_data} / MB &nbsp;|&nbsp;
                            SMS: {plan.ror_sms} / msg
                        </div>
                    </button>
                {/each}
            </div>
            <div class="btn-row">
                <button class="btn btn-secondary" onclick={() => step = 1}>← Back</button>
                <button class="btn btn-primary"
                        disabled={!selected.ratePlanId || loading}
                        onclick={activate}>
                    {loading ? 'Activating...' : 'Activate'}
                </button>
            </div>

            <!-- STEP 3: Success -->
        {:else if step === 3}
            <div class="success">
                <div class="success-icon">✓</div>
                <h2>You're all set!</h2>
                <p>Your number <strong>{selected.msisdn}</strong> has been activated.</p>
                <a href="/profile" class="btn btn-primary">Go to Dashboard</a>
            </div>
        {/if}

    </div>
</div>

<style>
    .onboarding-page { display: flex; align-items: center; justify-content: center; min-height: 80vh; }
    .onboarding-card { width: 100%; max-width: 560px; padding: 2.5rem; }

    .steps { display: flex; align-items: center; justify-content: center;
        gap: 0.5rem; margin-bottom: 2rem; font-size: 0.85rem; }
    .step { padding: 0.35rem 0.75rem; border-radius: 999px;
        background: var(--surface); color: var(--text-muted); }
    .step.active { background: var(--red); color: white; font-weight: 600; }
    .step.done   { background: var(--green, #22c55e); color: white; }
    .step-divider { color: var(--text-muted); }

    h2 { font-size: 1.35rem; font-weight: 700; margin-bottom: 0.25rem; }
    .subtitle { color: var(--text-muted); font-size: 0.875rem; margin-bottom: 1.25rem; }

    .number-grid { display: grid; grid-template-columns: repeat(3, 1fr);
        gap: 0.6rem; margin-bottom: 1.25rem; max-height: 280px; overflow-y: auto; }
    .number-btn { padding: 0.6rem 0.4rem; border: 1px solid var(--border);
        border-radius: var(--radius-sm); background: var(--surface);
        cursor: pointer; font-size: 0.8rem; transition: all 0.15s; }
    .number-btn:hover   { border-color: var(--red); }
    .number-btn.selected { border-color: var(--red); background: rgba(var(--red-rgb, 239,68,68), 0.1);
        font-weight: 600; }

    .plan-list { display: flex; flex-direction: column; gap: 0.75rem; margin-bottom: 1.25rem; }
    .plan-card { text-align: left; padding: 1rem; border: 1px solid var(--border);
        border-radius: var(--radius-sm); background: var(--surface);
        cursor: pointer; transition: all 0.15s; }
    .plan-card:hover    { border-color: var(--red); }
    .plan-card.selected { border-color: var(--red); background: rgba(var(--red-rgb, 239,68,68), 0.07); }
    .plan-name  { font-weight: 700; font-size: 1rem; }
    .plan-price { color: var(--red); font-weight: 600; margin: 0.2rem 0; }
    .plan-details { font-size: 0.78rem; color: var(--text-muted); }

    .btn-row { display: flex; gap: 0.75rem; justify-content: flex-end; }
    .full-width { width: 100%; }

    .success { text-align: center; padding: 1rem 0; }
    .success-icon { font-size: 3rem; color: #22c55e; margin-bottom: 0.75rem; }
    .success h2 { margin-bottom: 0.5rem; }
    .success p  { color: var(--text-muted); margin-bottom: 1.5rem; }

    .error-msg { background: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.2);
        color: #EF4444; padding: 0.75rem; border-radius: var(--radius-sm);
        font-size: 0.85rem; margin-bottom: 1rem; }
</style>