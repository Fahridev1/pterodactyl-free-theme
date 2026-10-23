<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Manajemen Panel</title>
<style>
:root{--bg:#0b1630;--bg2:#0f2147;--card:rgba(255,255,255,.07);--line:rgba(255,255,255,.12);--tx:#e8eefb;--mut:#9fb0cf;--ac:#4f8cff;--ac2:#2f6bdc;--ok:#3ecf9a;--err:#ff7a8a}
*{box-sizing:border-box}
html,body{margin:0}
body{font:14px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:var(--tx);background:radial-gradient(1200px 600px at 10% -10%,#17306a 0,transparent 60%),linear-gradient(160deg,var(--bg),var(--bg2));min-height:100vh;padding:16px;overflow-x:hidden}
.wrap{max-width:1040px;margin:0 auto;display:grid;gap:16px}
header{display:flex;flex-wrap:wrap;gap:8px 16px;align-items:center;justify-content:space-between}
h1{font-size:20px;margin:0}
h2{font-size:15px;margin:0 0 12px}
a{color:var(--ac);text-decoration:none}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);min-width:0}
.muted{color:var(--mut)}
.badge{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:600;border:1px solid var(--line);background:rgba(79,140,255,.14);white-space:nowrap}
.badge.superadmin{background:rgba(79,140,255,.32)}
.badge.user{background:rgba(255,255,255,.07);color:var(--mut)}
.flash{padding:10px 14px;border-radius:10px;border:1px solid var(--line)}
.flash.ok{background:rgba(62,207,154,.12);border-color:rgba(62,207,154,.4);color:var(--ok)}
.flash.err{background:rgba(255,122,138,.12);border-color:rgba(255,122,138,.4);color:var(--err)}
.sw-row{display:flex;gap:16px;align-items:center;justify-content:space-between;flex-wrap:wrap}
.sw{position:relative;display:inline-block;width:54px;height:30px;flex:none}
.sw input{opacity:0;width:100%;height:100%;position:absolute;inset:0;margin:0;cursor:pointer;z-index:1}
.sw i{position:absolute;inset:0;border-radius:999px;background:#33425f;transition:.2s}
.sw i:before{content:"";position:absolute;width:24px;height:24px;left:3px;top:3px;border-radius:50%;background:#fff;transition:.2s}
.sw input:checked+i{background:var(--ac2)}
.sw input:checked+i:before{transform:translateX(24px)}
.sw input:focus-visible+i{outline:2px solid var(--ac);outline-offset:2px}
table{width:100%;border-collapse:collapse}
th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--mut);text-align:left;padding:8px 10px;border-bottom:1px solid var(--line)}
td{padding:10px;border-bottom:1px solid var(--line);vertical-align:middle;overflow-wrap:anywhere}
tr:last-child td{border-bottom:0}
.empty{padding:14px;text-align:center;color:var(--mut)}
form.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px}
label{display:grid;gap:4px;font-size:12px;color:var(--mut)}
input[type=text],input[type=email],input[type=password],input[type=search],select{width:100%;padding:9px 11px;border-radius:9px;border:1px solid var(--line);background:rgba(0,0,0,.25);color:var(--tx);font:inherit}
button,.btn{padding:9px 16px;border-radius:9px;border:0;background:var(--ac2);color:#fff;font:600 14px system-ui;cursor:pointer}
button:hover{background:var(--ac)}
.bar{display:flex;gap:8px;margin-bottom:12px}
.bar input{flex:1;min-width:0}
.acts{display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end}
.acts form{display:inline-flex;gap:6px;margin:0}
.btn-s{padding:5px 10px;font-size:12px;border-radius:8px;background:rgba(79,140,255,.18);color:var(--tx);border:1px solid var(--line);text-decoration:none;display:inline-block;cursor:pointer;font-weight:600}
.btn-s:hover{background:rgba(79,140,255,.34)}
.btn-s.danger{background:rgba(255,122,138,.14);border-color:rgba(255,122,138,.4);color:var(--err)}
.badge.lock{background:rgba(255,255,255,.07);color:var(--mut)}
.badge.warn{background:rgba(255,200,87,.14);color:#ffc857}
td select{padding:5px 8px;width:auto}
.pager{display:flex;gap:12px;justify-content:space-between;margin-top:12px;font-size:13px}
@media (max-width:640px){
  body{padding:10px}
  thead{display:none}
  table,tbody,tr,td{display:block;width:100%}
  tr{padding:10px 0;border-bottom:1px solid var(--line)}
  tr:last-child{border-bottom:0}
  td{border:0;padding:3px 0;display:flex;justify-content:space-between;gap:12px;text-align:right}
  td:before{content:attr(data-l);color:var(--mut);text-align:left;flex:none}
}
</style>
</head>
<body>
<div class="wrap">

<header>
  <div>
    <h1>Manajemen Panel</h1>
    <div class="muted">Masuk sebagai <b>{{ $me->username }}</b> <span class="badge {{ $role }}">{{ $role }}</span></div>
  </div>
  <a href="/">&larr; Kembali ke panel</a>
</header>

@if (session('ap_ok'))<div class="flash ok">{{ session('ap_ok') }}</div>@endif
@if (session('ap_err'))<div class="flash err">{{ session('ap_err') }}</div>@endif
@if ($errors->any())<div class="flash err">{{ $errors->first() }}</div>@endif

@if ((int) $me->id === 1)
<section class="card">
  <form method="post" action="{{ route('antipeep.toggle') }}" class="sw-row">
    @csrf
    <div>
      <h2 style="margin:0">Anti-Intip Mode</h2>
      <div class="muted">
        @if ($on) Nyala: server milik orang lain disembunyikan dari daftar dan tidak bisa dibuka. Hanya Superadmin (ID 1) yang melihat semua server.
        @else Mati: semua role bisa melihat semua server (hanya daftar, bukan akses konsol). @endif
      </div>
    </div>
    <input type="hidden" name="enabled" value="0">
    <label class="sw" aria-label="Anti-Intip Mode">
      <input type="checkbox" name="enabled" value="1" @if ($on) checked @endif onchange="this.form.submit()">
      <i></i>
    </label>
  </form>
</section>
@endif

@if (count($creatable))
<section class="card">
  <h2>Buat akun baru</h2>
  <form method="post" action="{{ route('antipeep.users.store') }}" class="grid" autocomplete="off">
    @csrf
    <label>Username<input type="text" name="username" value="{{ old('username') }}" required></label>
    <label>Email<input type="email" name="email" value="{{ old('email') }}" required></label>
    <label>Nama depan<input type="text" name="name_first" value="{{ old('name_first') }}" required></label>
    <label>Nama belakang<input type="text" name="name_last" value="{{ old('name_last') }}" required></label>
    <label>Password (min 8)<input type="password" name="password" minlength="8" required></label>
    <label>Role
      <select name="role">
        @foreach ($creatable as $r)<option value="{{ $r }}" @if (old('role') === $r) selected @endif>{{ $r }}</option>@endforeach
      </select>
    </label>
    <label>&nbsp;<button type="submit">Buat akun</button></label>
  </form>
</section>
@endif

@if ($users)
<section class="card">
  <h2>User</h2>
  <table>
    <thead><tr><th>ID</th><th>Username</th><th>Email</th><th>Role</th><th>Server</th>@if ($role === 'superadmin')<th></th>@endif</tr></thead>
    <tbody>
    @forelse ($users as $u)
      @php($ur = \Pterodactyl\AntiPeep\AntiPeep::role($u))
      <tr>
        <td data-l="ID">{{ $u->id }}</td>
        <td data-l="Username">{{ $u->username }}</td>
        <td data-l="Email">{{ $u->email }}</td>
        <td data-l="Role">
          @if ($role === 'superadmin' && (int) $u->id !== 1)
            <form method="post" action="{{ route('antipeep.users.role', $u->id) }}" class="acts">
              @csrf
              <select name="role" aria-label="Role">
                @foreach (['admin', 'reseller', 'user'] as $r)<option value="{{ $r }}" @if ($ur === $r) selected @endif>{{ $r }}</option>@endforeach
              </select>
              <button type="submit" class="btn-s">Simpan</button>
            </form>
          @else
            <span class="badge {{ $ur }}">{{ $ur }}</span>
          @endif
        </td>
        <td data-l="Server">@if ($role === 'superadmin' || (int) $u->id === (int) $me->id){{ $u->servers_count }}@else - @endif</td>
        @if ($role === 'superadmin')
        <td data-l="Aksi">
          <div class="acts">
            <a class="btn-s" href="/admin/users/view/{{ $u->id }}">Kelola</a>
            @if ((int) $u->id !== 1 && (int) $u->id !== (int) $me->id)
            <form method="post" action="{{ route('antipeep.users.delete', $u->id) }}" onsubmit="return confirm('Hapus user ini?')">
              @csrf<button type="submit" class="btn-s danger">Hapus</button>
            </form>
            @endif
          </div>
        </td>
        @endif
      </tr>
    @empty
      <tr><td class="empty">Belum ada user.</td></tr>
    @endforelse
    </tbody>
  </table>
  <div class="pager">
    <span>@if ($users->previousPageUrl())<a href="{{ $users->previousPageUrl() }}">&larr; Sebelumnya</a>@endif</span>
    <span>@if ($users->nextPageUrl())<a href="{{ $users->nextPageUrl() }}">Berikutnya &rarr;</a>@endif</span>
  </div>
</section>
@endif

<section class="card">
  <h2>Server</h2>
  <form method="get" class="bar">
    <input type="search" name="q" value="{{ $q }}" placeholder="Cari nama server">
    <button type="submit">Cari</button>
  </form>
  <table>
    <thead><tr><th>ID</th><th>Nama</th><th>Pemilik</th><th>Node</th><th>Status</th><th></th></tr></thead>
    <tbody>
    @forelse ($servers as $s)
      @php($locked = $on && $role !== 'superadmin' && (int) $s->owner_id !== (int) $me->id)
      <tr>
        <td data-l="ID">{{ $s->id }}</td>
        <td data-l="Nama">{{ $s->name }}</td>
        <td data-l="Pemilik">{{ optional($s->user)->username ?? '-' }}</td>
        <td data-l="Node">{{ optional($s->node)->name ?? '-' }}</td>
        <td data-l="Status">
          @if ($s->isSuspended())<span class="badge warn">Suspended</span>
          @elseif ($s->status)<span class="badge">{{ $s->status }}</span>
          @else <span class="badge">Aktif</span>@endif
        </td>
        <td data-l="Aksi">
          <div class="acts">
            @if ($role === 'superadmin')
              <a class="btn-s" href="/admin/servers/view/{{ $s->id }}">Kelola</a>
              <form method="post" action="{{ route('antipeep.servers.suspend', $s->id) }}">
                @csrf<button type="submit" class="btn-s">{{ $s->isSuspended() ? 'Aktifkan' : 'Suspend' }}</button>
              </form>
              <form method="post" action="{{ route('antipeep.servers.delete', $s->id) }}" onsubmit="return confirm('Hapus server ini? Tidak bisa dibatalkan.')">
                @csrf<button type="submit" class="btn-s danger">Hapus</button>
              </form>
            @elseif ($locked)
              <span class="badge lock">Terkunci</span>
            @else
              <a class="btn-s" href="/server/{{ $s->uuidShort }}">Buka</a>
            @endif
          </div>
        </td>
      </tr>
    @empty
      <tr><td class="empty">Tidak ada server.</td></tr>
    @endforelse
    </tbody>
  </table>
  <div class="pager">
    <span>@if ($servers->previousPageUrl())<a href="{{ $servers->previousPageUrl() }}">&larr; Sebelumnya</a>@endif</span>
    <span>@if ($servers->nextPageUrl())<a href="{{ $servers->nextPageUrl() }}">Berikutnya &rarr;</a>@endif</span>
  </div>
</section>

</div>
</body>
</html>
