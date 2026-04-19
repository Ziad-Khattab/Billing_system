

export const index = 1;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/fallbacks/error.svelte.js')).default;
export const imports = ["_app/immutable/nodes/1.BN7UOv4I.js","_app/immutable/chunks/BtdNFNN8.js","_app/immutable/chunks/WTv8AUqD.js","_app/immutable/chunks/D9FQP20W.js"];
export const stylesheets = [];
export const fonts = [];
