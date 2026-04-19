# Frontend Practice Guide — Build SvelteKit Step by Step

## Step 0: Setup SvelteKit

```bash
# From project root (Billing_system/)
npx -y sv create frontend --template minimal --types jsdoc --no-add-ons --install npm

# Verify it works
cd frontend
npm run dev
# Open http://localhost:5173 — you should see a blank Svelte page
```

## Step 1: Add Logo

Copy the FMRZ logo to `frontend/static/logo.png`.
Files in `static/` are served at root: `http://localhost:5173/logo.png`

## Step 2: Design System (app.css)

Open `frontend/src/app.css` and replace with the design tokens.
Reference: `docs/reference/` — compare your work with the completed version.

**Key CSS concepts to learn:**
- CSS custom properties (`--red: #E00800`) — reusable color variables
- `backdrop-filter: blur(20px)` — glassmorphism effect
- `@keyframes` — CSS animations
- CSS Grid (`grid-template-columns: repeat(3, 1fr)`) — responsive layouts

## Step 3: Layout (+layout.svelte)

The layout wraps ALL pages. Create `src/routes/+layout.svelte`.

**What to learn:**
- `$state()` — Svelte 5 reactive state (replaces `let` reactivity in Svelte 4)
- `$effect()` — runs side effects when state changes (like React's useEffect)
- `{#if}` / `{:else if}` / `{:else}` — conditional rendering
- `class:active={condition}` — conditional CSS classes
- `{@render children()}` — renders the child page content

## Step 4: Build Pages (one at a time)

**Order:**
1. Landing page (`src/routes/+page.svelte`)
2. Packages page (`src/routes/packages/+page.svelte`)
3. Login page (`src/routes/login/+page.svelte`)
4. Register page (`src/routes/register/+page.svelte`)
5. Customer dashboard (`src/routes/dashboard/+page.svelte`)
6. Admin dashboard (`src/routes/admin/+page.svelte`)
7. Admin customers (`src/routes/admin/customers/+page.svelte`)
8. Admin contracts (`src/routes/admin/contracts/+page.svelte`)
9. Admin billing (`src/routes/admin/billing/+page.svelte`)

**For each page:**
1. Create the folder + `+page.svelte` file
2. Read the reference version in the frontend source
3. Type it yourself
4. `npm run dev` — check in browser

## Key Svelte 5 Patterns Used

```svelte
<!-- Reactive state -->
<script>
  let count = $state(0);           // reactive variable
  let items = $state([]);          // reactive array

  $effect(() => {                   // runs on mount + when dependencies change
    fetch('/api/data').then(r => r.json()).then(d => items = d);
  });
</script>

<!-- Event handling -->
<button onclick={() => count++}>Click</button>
<form onsubmit={handleSubmit}>

<!-- Two-way binding -->
<input bind:value={username} />

<!-- Conditional + Loop -->
{#if loading}
  <p>Loading...</p>
{:else}
  {#each items as item}
    <div>{item.name}</div>
  {/each}
{/if}
```

## Running Both Servers

Terminal 1 (backend):
```bash
# Deploy WAR to Tomcat or use tomcat plugin
cd Billing_system
./mvnw clean package
# copy WAR to Tomcat
```

Terminal 2 (frontend):
```bash
cd Billing_system/frontend
npm run dev
```

Backend: http://localhost:8080
Frontend: http://localhost:5173
