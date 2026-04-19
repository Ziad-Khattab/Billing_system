

export const index = 7;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/dashboard/_page.svelte.js')).default;
export const imports = ["_app/immutable/nodes/7.BSey8Oot.js","_app/immutable/chunks/BtdNFNN8.js","_app/immutable/chunks/D9FQP20W.js"];
export const stylesheets = ["_app/immutable/assets/7.BocrZanK.css"];
export const fonts = [];
