

export const index = 5;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/admin/contracts/_page.svelte.js')).default;
export const imports = ["_app/immutable/nodes/5.C0KdeDHX.js","_app/immutable/chunks/BtdNFNN8.js","_app/immutable/chunks/D9FQP20W.js"];
export const stylesheets = [];
export const fonts = [];
