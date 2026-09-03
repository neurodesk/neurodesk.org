(function () {
	const servers = [
		{ id: 1, url: 'https://play-america.neurodesk.org' },
		{ id: 2, url: 'https://play-europe.neurodesk.org' },
		{ id: 3, url: 'https://play.neurodesk.cloud.edu.au' },
	];

	async function check(url) {
		const start = performance.now();
		try {
			await fetch(url, { mode: 'no-cors', cache: 'no-cache', method: 'HEAD' });
			return Math.round(performance.now() - start);
		} catch (e) {
			return -1;
		}
	}

	async function runPingTest() {
		const btn = document.getElementById('ping-btn');
		if (btn) {
			btn.disabled = true;
			btn.innerText = 'Testing...';
		}

		servers.forEach((s) => {
			const card = document.getElementById('card-' + s.id);
			if (card) card.classList.remove('ping-winner');
			const t = document.getElementById('ping-' + s.id);
			const st = document.getElementById('status-' + s.id);
			if (t) t.innerText = '-- ms';
			if (st) st.innerText = 'Pinging...';
		});

		const results = await Promise.all(servers.map((s) => check(s.url)));
		const finalData = servers.map((s, i) => ({ ...s, time: results[i] }));

		finalData.forEach((item) => {
			const el = document.getElementById('ping-' + item.id);
			const status = document.getElementById('status-' + item.id);
			if (!el || !status) return;
			if (item.time === -1) {
				el.innerText = 'Error';
				el.style.color = 'var(--sl-color-red, #d73a49)';
				status.innerText = 'Unreachable';
			} else {
				el.innerText = item.time + ' ms';
				status.innerText = 'Online';
			}
		});

		const valid = finalData.filter((d) => d.time !== -1);
		if (valid.length > 0) {
			valid.sort((a, b) => a.time - b.time);
			const winner = valid[0];
			const winCard = document.getElementById('card-' + winner.id);
			if (winCard) winCard.classList.add('ping-winner');
			const winStatus = document.getElementById('status-' + winner.id);
			if (winStatus) {
				winStatus.innerText = 'Recommended';
				winStatus.style.fontWeight = 'bold';
			}
		}
		if (btn) {
			btn.disabled = false;
			btn.innerText = 'Re-test latency';
		}
	}

	function init() {
		const btn = document.getElementById('ping-btn');
		if (btn) btn.addEventListener('click', runPingTest);
		runPingTest();
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
})();
