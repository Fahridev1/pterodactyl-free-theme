/* NightPanel - helper tema + pop up sambutan.
   Banyak komponen panel memakai class acak (styled-components), jadi CSS saja tidak cukup.
   Script ini membaca warna aslinya lalu membuatnya transparan (efek kaca) dan mewarnai tombol. */
(function () {
  'use strict';

  var SKIP = { SVG: 1, PATH: 1, CANVAS: 1, IMG: 1, SCRIPT: 1, STYLE: 1, INPUT: 1, SELECT: 1,
               TEXTAREA: 1, BUTTON: 1, OPTION: 1, HTML: 1, BODY: 1, HEAD: 1 };

  function parse(c) {
    var m = c && c.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    var p = m[1].split(/[ ,\/]+/).filter(Boolean).map(parseFloat);
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  }

  function hsl(c) {
    var r = c.r / 255, g = c.g / 255, b = c.b / 255;
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, h = 0, s = 0, d = mx - mn;
    if (d) {
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
      else if (mx === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h *= 60;
    }
    return { h: h, s: s * 100, l: l * 100 };
  }

  function glass(el) {
    var c = parse(getComputedStyle(el).backgroundColor);
    if (!c || c.a < 1) return;
    var x = hsl(c);
    // abu-abu kebiruan gelap = palet bawaan panel (gray 600-900 dan black)
    if (x.h < 195 || x.h > 230 || x.s < 8 || x.s > 40 || x.l < 9 || x.l > 40) return;
    el.style.setProperty('background-color',
      'rgba(' + c.r + ',' + c.g + ',' + c.b + ',' + (x.l < 20 ? 0.62 : 0.52) + ')', 'important');
    var big = el.offsetWidth * el.offsetHeight > window.innerWidth * window.innerHeight * 0.6;
    if (!big && !(el.parentElement && el.parentElement.closest('[data-night-blur]'))) {
      el.setAttribute('data-night-blur', '1');
      el.style.setProperty('-webkit-backdrop-filter', 'blur(8px)');
      el.style.setProperty('backdrop-filter', 'blur(8px)');
    }
  }

  function button(el) {
    var c = parse(getComputedStyle(el).backgroundColor);
    if (!c || c.a < 0.9) return;
    var x = hsl(c), cls = null;
    if (x.s >= 35 && x.h >= 200 && x.h <= 285) cls = 'n-btn-primary';
    else if (x.s >= 30 && x.h >= 80 && x.h <= 170) cls = 'n-btn-green';
    else if (x.s >= 40 && (x.h <= 15 || x.h >= 345)) cls = 'n-btn-red';
    if (cls && !el.classList.contains(cls)) el.classList.add(cls);
  }

  function inTerminal(el) { return el.closest && el.closest('.xterm'); }

  function process(el) {
    if (el.nodeType !== 1 || !el.isConnected || inTerminal(el)) return;
    if (el.tagName === 'BUTTON') button(el);
    else if (!SKIP[el.tagName]) glass(el);
  }

  function scan(root) {
    if (root.nodeType !== 1 || inTerminal(root)) return;
    process(root);
    var all = root.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) process(all[i]);
  }

  var queue = [], timer = null;
  function enqueue(node) {
    queue.push(node);
    if (timer) return;
    timer = setTimeout(function () {
      var work = queue; queue = []; timer = null;
      for (var i = 0; i < work.length; i++) { try { scan(work[i]); } catch (e) { /* abaikan */ } }
    }, 120);
  }

  function welcome() {
    var u = window.PterodactylUser;
    if (!u || !u.username) return;
    try {
      if (sessionStorage.getItem('night_welcome')) return;
      sessionStorage.setItem('night_welcome', '1');
    } catch (e) { /* storage diblokir: tampilkan saja */ }

    var box = document.createElement('div'); box.className = 'night-welcome';
    var moon = document.createElement('div'); moon.className = 'night-welcome-moon'; moon.textContent = '\uD83C\uDF19';
    var txt = document.createElement('div');
    var t = document.createElement('div'); t.className = 'night-welcome-title';
    t.textContent = 'Hai, selamat datang @' + u.username + '!';
    var s = document.createElement('div'); s.className = 'night-welcome-sub';
    s.textContent = 'Semoga harimu menyenangkan.';
    txt.appendChild(t); txt.appendChild(s); box.appendChild(moon); box.appendChild(txt);

    function hide() { box.classList.remove('show'); setTimeout(function () { box.remove(); }, 600); }
    box.addEventListener('click', hide);
    document.body.appendChild(box);
    requestAnimationFrame(function () { requestAnimationFrame(function () { box.classList.add('show'); }); });
    setTimeout(hide, 5000);
  }

  function start() {
    enqueue(document.body);
    new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var m = muts[i];
        if (inTerminal(m.target)) continue;
        if (m.type === 'attributes') { if (m.target.tagName === 'BUTTON') enqueue(m.target); continue; }
        for (var j = 0; j < m.addedNodes.length; j++) enqueue(m.addedNodes[j]);
      }
    }).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
    welcome();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
