const ICON_COPY = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>';
const ICON_OK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 12l5 5L20 6"/></svg>';

document.querySelectorAll('.cite').forEach((card) => {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'cite__copy';
  btn.title = 'Copy citation';
  btn.setAttribute('aria-label', 'Copy citation');
  btn.innerHTML = ICON_COPY;

  btn.addEventListener('click', async () => {
    const titleStrong = card.querySelector('p strong');
    const title = titleStrong?.innerText.trim() ?? '';
    const meta = card.querySelector('.cite__meta')?.innerText.trim() ?? '';
    const link = card.querySelector('a[href*="doi.org"], a[href*="osf.io"]');
    const url = link?.href ?? '';
    const text = [title, meta, url].filter(Boolean).join(' ');

    try {
      await navigator.clipboard.writeText(text);
      btn.innerHTML = ICON_OK;
      btn.classList.add('cite__copy--ok');
    } catch {
      btn.innerHTML = ICON_COPY;
    }
    setTimeout(() => {
      btn.innerHTML = ICON_COPY;
      btn.classList.remove('cite__copy--ok');
    }, 1500);
  });

  card.appendChild(btn);
});
