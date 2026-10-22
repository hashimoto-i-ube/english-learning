// ULSハブ内では window.ULSHub 経由、ブラウザ単体では localStorage に保存する。
window.ToolStorage = (() => { const hub = window.ULSHub; const p = 'tool:';
  if (hub) return { ready: hub.ready, getItem: k => hub.storage.getItem(k), setItem: (k, v) => hub.storage.setItem(k, v), removeItem: k => hub.storage.removeItem(k) };
  return { ready: Promise.resolve(), getItem: async k => localStorage.getItem(p + k), setItem: async (k, v) => localStorage.setItem(p + k, v), removeItem: async k => localStorage.removeItem(p + k) }; })();
window.openExternal = url => (window.ULSHub && window.ULSHub.openExternal) ? window.ULSHub.openExternal(url) : window.open(url, '_blank', 'noopener');
