

export const index = 4;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/admin/billing/_page.svelte.js')).default;
export const imports = ["_app/immutable/nodes/4.BE9dbcvX.js","_app/immutable/chunks/BtdNFNN8.js","_app/immutable/chunks/D9FQP20W.js"];
export const stylesheets = [];
export const fonts = [];
