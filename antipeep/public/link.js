(function () {
  var HREF = '/admin/antipeep';
  if (location.pathname.indexOf(HREF) === 0) return;
  function add() {
    var menu = document.querySelector('.sidebar-menu');
    if (menu) {
      if (!menu.querySelector('[data-antipeep]')) {
        var li = document.createElement('li');
        li.setAttribute('data-antipeep', '1');
        li.innerHTML = '<a href="' + HREF + '"><i class="fa fa-shield"></i> <span>Anti-Intip &amp; Role</span></a>';
        menu.appendChild(li);
      }
      return;
    }
    if (document.getElementById('antipeep-pill')) return;
    var a = document.createElement('a');
    a.id = 'antipeep-pill';
    a.href = HREF;
    a.textContent = 'Manajemen';
    a.style.cssText = 'position:fixed;left:14px;bottom:14px;z-index:9999;padding:8px 14px;border-radius:999px;' +
      'background:rgba(15,31,61,.92);color:#e6edf7;font:600 12px system-ui,sans-serif;text-decoration:none;' +
      'border:1px solid rgba(255,255,255,.15);backdrop-filter:blur(8px)';
    document.body.appendChild(a);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add);
  else add();
})();
