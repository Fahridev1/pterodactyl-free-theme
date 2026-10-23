<?php

namespace Pterodactyl\AntiPeep;

use Closure;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\User;

/**
 * Dipasang di akhir grup middleware web, client-api, dan application-api
 * (setelah login dan route binding), jadi user dan model rute sudah tersedia.
 *
 *  1. PTLA (Application API) hanya untuk admin ke atas.
 *  2. Anti-Intip: MEMBUKA server orang lain ditolak, dan DAFTAR server orang lain disembunyikan
 *     (hanya Superadmin / user ID 1 yang melihat semuanya).
 *  3. Hierarki role saat membuat/mengubah/menghapus akun (form admin dan Application API).
 */
class AntiPeepGuard
{
    /** Halaman & endpoint yang menampilkan daftar server (atau jumlahnya). */
    private const LIST_PATHS = [
        'admin/servers',
        'admin/users',
        'admin/users/view/*',
        'admin/nodes',
        'admin/nodes/view/*/servers',
        'admin/antipeep',
        'api/application/servers',
        'api/application/users',
        'api/application/users/*',
    ];

    public function handle(Request $request, Closure $next)
    {
        $actor = $request->user();
        if (!$actor) {
            return $next($request);
        }
        $role = AntiPeep::role($actor);

        // 1. PTLA
        if ($request->is('api/application', 'api/application/*') && AntiPeep::rank($role) < AntiPeep::rank('admin')) {
            return $this->deny($request, 'Application API (PTLA) hanya untuk role admin ke atas.');
        }

        if ($role === 'superadmin') {
            return $next($request);
        }

        // 2. Anti-Intip
        if (AntiPeep::enabled()) {
            $server = $this->resolve($request, 'server', Server::class) ?? $this->serverFromPage($request);
            if ($server && (int) $server->owner_id !== (int) $actor->id) {
                return $this->deny($request, 'Anti-Intip aktif: kamu hanya boleh membuka server milikmu sendiri.');
            }

            // 2b. Sembunyikan server orang lain dari semua halaman/API daftar.
            // Hanya untuk request baca (GET/HEAD) supaya pengecekan internal Panel saat
            // hapus node/user/egg (misal "masih ada server?") tetap melihat semua server.
            $dashboardAll = $request->is('api/client') && in_array($request->query('type'), ['admin', 'admin-all'], true);
            if ($request->isMethodSafe() && ($dashboardAll || $request->is(...self::LIST_PATHS))) {
                $ownerId = (int) $actor->id;
                Server::addGlobalScope('antipeep', function (Builder $query) use ($ownerId) {
                    $query->where('servers.owner_id', $ownerId);
                });
            }
        }

        // 3. Hierarki role
        if (!$request->isMethodSafe()) {
            if ($request->is('admin/users/new', 'api/application/users')) {
                $want = $request->boolean('root_admin') ? 'admin' : 'user';
                if (!AntiPeep::canCreate($actor, $want)) {
                    return $this->deny($request, 'Role kamu tidak boleh membuat akun dengan role ini.');
                }
            } elseif ($request->is('admin/users/*', 'api/application/users/*')) {
                $target = $this->resolve($request, 'user', User::class);
                if ($target) {
                    if (!AntiPeep::canManage($actor, $target)) {
                        return $this->deny($request, 'Role kamu tidak boleh mengelola akun ini.');
                    }
                    if ($request->has('root_admin')
                        && $request->boolean('root_admin') !== (bool) $target->root_admin
                        && !AntiPeep::canCreate($actor, $request->boolean('root_admin') ? 'admin' : 'user')) {
                        return $this->deny($request, 'Role kamu tidak boleh mengubah level admin.');
                    }
                }
            }
        }

        return $next($request);
    }

    /** Halaman dashboard /server/{id}/... adalah shell React tanpa route parameter, jadi ambil dari URL. */
    private function serverFromPage(Request $request): ?Server
    {
        if (!$request->is('server/*')) {
            return null;
        }
        $id = (string) $request->segment(2);
        if ($id === '' || !preg_match('/^[a-z0-9-]+$/i', $id)) {
            return null;
        }

        return Server::query()->where('uuidShort', $id)->orWhere('uuid', $id)->first();
    }

    private function resolve(Request $request, string $param, string $class)
    {
        $value = $request->route($param);
        if ($value instanceof $class) {
            return $value;
        }
        if (!is_scalar($value) || (string) $value === '') {
            return null;
        }
        $value = (string) $value;
        if ($class === Server::class) {
            return Server::query()
                ->where('id', ctype_digit($value) ? (int) $value : 0)
                ->orWhere('uuidShort', $value)
                ->orWhere('uuid', $value)
                ->first();
        }

        return ctype_digit($value) ? $class::query()->find((int) $value) : null;
    }

    private function deny(Request $request, string $message)
    {
        if ($request->expectsJson() || $request->is('api/*')) {
            return response()->json(['errors' => [[
                'code' => 'AntiPeepDenied',
                'status' => '403',
                'detail' => $message,
            ]]], 403);
        }

        return response()->view('antipeep::denied', ['message' => $message], 403);
    }
}
