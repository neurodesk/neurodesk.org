document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-expand]');
  if (!btn) return;
  const expand = btn.dataset.expand === 'all';
  const target = btn.dataset.target;
  if (!target) return;
  document.querySelectorAll(target).forEach((d) => {
    d.open = expand;
  });
});
