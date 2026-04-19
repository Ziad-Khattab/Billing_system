

export const index = 3;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/admin/_page.svelte.js')).default;
export const imports = ["_app/immutable/nodes/3.CL6JmnMq.js","_app/immutable/chunks/BtdNFNN8.js","_app/immutable/chunks/D9FQP20W.js"];
export const stylesheets = ["_app/immutable/assets/3.Pwa25-hj.css"];
export const fonts = [];
