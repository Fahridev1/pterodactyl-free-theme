/* NightPanel Admin - indikator proteksi DDoS (NightGuard) di navbar dan dashboard admin.
   Membaca /themes/night/ddos-status.json (ditulis NightGuard). Kalau file tidak ada,
   semua elemen disembunyikan sehingga aman dipakai tanpa NightGuard. */
(function () {
  'use strict';

  var URL_STATUS = '/themes/night/ddos-status.json';
  var chipLi = null, chipEl = null, chipLabel = null, card = null, nums = {}, badge = null, sub = null;

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function fmtTime(ts) {
    if (!ts) return '-';
    var d = new Date(ts * 1000), p = function (n) { return (n < 10 ? '0' : '') + n; };
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  }

  function mountChip() {
    if (chipLi) return;
    var menu = document.querySelector('.navbar-custom-menu > .navbar-nav');
    if (!menu) return;
    chipLi = el('li', 'ng-chip-li');
    chipEl = el('a', 'ng-chip');
    chipEl.href = '/admin';
    chipEl.appendChild(el('span', 'ng-dot'));
    chipLabel = el('span', 'ng-chip-label', 'Memuat...');
    chipEl.appendChild(chipLabel);
    chipLi.appendChild(chipEl);
    menu.insertBefore(chipLi, menu.firstChild);
  }

  function stat(key, label) {
    var box = el('div', 'ng-stat');
    nums[key] = el('div', 'ng-stat-num', '-');
    box.appendChild(nums[key]);
    box.appendChild(el('div', 'ng-stat-label', label));
    return box;
  }

  function mountCard() {
    if (card || location.pathname.replace(/\/+$/, '') !== '/admin') return;
    var content = document.querySelector('section.content');
    if (!content) return;
    var row = el('div', 'row'), col = el('div', 'col-xs-12');
    card = el('div', 'box box-primary ng-card');
    var head = el('div', 'box-header with-border');
    var title = el('h3', 'box-title', '\uD83D\uDEE1\uFE0F Proteksi DDoS (NightGuard)');
    badge = el('span', 'ng-badge', 'Memuat...');
    title.appendChild(badge);
    head.appendChild(title);
    var body = el('div', 'box-body'), grid = el('div', 'ng-grid');
    grid.appendChild(stat('conn', 'Koneksi aktif'));
    grid.appendChild(stat('syn', 'SYN_RECV'));
    grid.appendChild(stat('banned', 'IP diblokir'));
    grid.appendChild(stat('offenders', 'Pelanggar live'));
    grid.appendChild(stat('attacks', 'Serangan tercatat'));
    sub = el('div', 'ng-sub');
    body.appendChild(grid); body.appendChild(sub);
    card.appendChild(head); card.appendChild(body);
    col.appendChild(card); row.appendChild(col);
    content.insertBefore(row, content.firstChild);
  }

  function setState(cls, chipText, badgeText) {
    ['ng-ok', 'ng-warn', 'ng-attack'].forEach(function (c) {
      if (chipEl) chipEl.classList.remove(c);
      if (card) card.classList.remove(c);
    });
    if (chipEl) { chipEl.classList.add(cls); chipLabel.textContent = chipText; }
    if (card) { card.classList.add(cls); badge.textContent = badgeText; }
  }

  function render(s) {
    mountChip(); mountCard();
    if (chipLi) chipLi.style.display = '';
    if (card && card.parentNode) card.parentNode.parentNode.style.display = '';
    var stale = (Date.now() / 1000 - s.updated) > 60;
    if (stale) setState('ng-warn', 'Proteksi tidak merespons', 'Daemon tidak merespons');
    else if (s.mode === 'attack') setState('ng-attack', 'Diserang! Mode ketat', 'DISERANG - mode ketat aktif');
    else setState('ng-ok', 'Proteksi aktif', 'Aman');
    if (card) {
      ['conn', 'syn', 'banned', 'offenders', 'attacks'].forEach(function (k) { nums[k].textContent = s[k]; });
      sub.textContent = 'Diperbarui ' + fmtTime(s.updated) + '  |  Serangan terakhir: ' + fmtTime(s.last_attack) +
        '  |  Blokir via ' + (s.backend === 'ipset' ? 'firewall' : 'nginx') + (s.cf ? '  |  Cloudflare aktif' : '');
    }
  }

  function hide() {
    if (chipLi) chipLi.style.display = 'none';
    if (card && card.parentNode) card.parentNode.parentNode.style.display = 'none';
  }

  function poll() {
    fetch(URL_STATUS + '?t=' + Date.now(), { cache: 'no-store', credentials: 'same-origin' })
      .then(function (r) { if (!r.ok) throw new Error('nf'); return r.json(); })
      .then(render)
      .catch(hide);
  }

  function start() { poll(); setInterval(poll, 10000); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
