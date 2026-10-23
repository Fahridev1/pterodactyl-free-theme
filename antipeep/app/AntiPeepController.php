<?php

namespace Pterodactyl\AntiPeep;

use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\User;
use Pterodactyl\Services\Servers\ServerDeletionService;
use Pterodactyl\Services\Servers\SuspensionService;
use Pterodactyl\Services\Users\UserCreationService;
use Pterodactyl\Services\Users\UserDeletionService;

class AntiPeepController extends Controller
{
    public function index(Request $request)
    {
        $me = $request->user();
        $role = AntiPeep::role($me);
        $on = AntiPeep::enabled();

        // Superadmin (user ID 1) melihat semua server.
        // Role lain: mode nyala = hanya server miliknya, mode mati = semua (daftar saja).
        $servers = Server::query()->with(['user:id,username', 'node:id,name'])->orderByDesc('id');
        if ($role !== 'superadmin' && $on) {
            $servers->where('owner_id', $me->id);
        }
        $q = trim((string) $request->query('q', ''));
        if ($q !== '') {
            $servers->where('name', 'like', '%' . addcslashes($q, '%_\\') . '%');
        }
        $servers = $servers->paginate(15, ['*'], 'sp')->withQueryString();

        $users = null;
        if (in_array($role, ['superadmin', 'admin', 'reseller'], true)) {
            $uq = User::query()->withCount('servers')->orderBy('id');
            if ($role === 'admin') {
                $uq->where(function ($w) use ($me) {
                    $w->where('id', $me->id)->orWhereIn('role', ['reseller', 'user']);
                });
            } elseif ($role === 'reseller') {
                $uq->where(function ($w) use ($me) {
                    $w->where('id', $me->id)->orWhere('created_by', $me->id);
                });
            }
            $users = $uq->paginate(15, ['*'], 'up')->withQueryString();
        }

        return view('antipeep::index', [
            'me' => $me,
            'role' => $role,
            'on' => $on,
            'servers' => $servers,
            'users' => $users,
            'creatable' => AntiPeep::creatableRoles($me),
            'q' => $q,
        ]);
    }

    public function toggle(Request $request)
    {
        $this->superadmin($request);
        AntiPeep::setEnabled($request->boolean('enabled'));

        return $this->ok('Anti-Intip Mode ' . (AntiPeep::enabled() ? 'dinyalakan.' : 'dimatikan.'));
    }

    public function storeUser(Request $request, UserCreationService $creation)
    {
        $me = $request->user();
        $data = $request->validate([
            'username' => ['required', 'string', 'between:3,191', 'regex:/^[a-z0-9]([\w\.-]*)[a-z0-9]$/i'],
            'email' => ['required', 'email', 'max:191'],
            'name_first' => ['required', 'string', 'max:191'],
            'name_last' => ['required', 'string', 'max:191'],
            'password' => ['required', 'string', 'min:8', 'max:191'],
            'role' => ['required', 'in:admin,reseller,user'],
        ]);
        abort_unless(AntiPeep::canCreate($me, $data['role']), 403, 'Role kamu tidak boleh membuat role ini.');

        try {
            $new = $creation->handle([
                'username' => $data['username'],
                'email' => $data['email'],
                'name_first' => $data['name_first'],
                'name_last' => $data['name_last'],
                'password' => $data['password'],
                'root_admin' => $data['role'] === 'admin',
            ]);
            DB::table('users')->where('id', $new->id)
                ->update(['role' => $data['role'], 'created_by' => $me->id]);
        } catch (\Throwable $e) {
            report($e);

            return back()->withInput($request->except('password'))
                ->with('ap_err', 'Gagal membuat user. Username atau email mungkin sudah dipakai.');
        }

        return $this->ok('Akun ' . $data['username'] . ' berhasil dibuat.');
    }

    // ------------------------------------------------------------ kontrol Superadmin

    public function setRole(Request $request, int $id)
    {
        $this->superadmin($request);
        $role = $request->validate(['role' => ['required', 'in:admin,reseller,user']])['role'];
        $target = User::query()->findOrFail($id);
        abort_if((int) $target->id === 1, 403, 'Superadmin (ID 1) tidak bisa diubah rolenya.');
        AntiPeep::setRole($target, $role);

        return $this->ok('Role ' . $target->username . ' diubah menjadi ' . $role . '.');
    }

    public function deleteUser(Request $request, UserDeletionService $deletion, int $id)
    {
        $me = $this->superadmin($request);
        $target = User::query()->findOrFail($id);
        abort_if((int) $target->id === 1 || (int) $target->id === (int) $me->id, 403, 'Akun ini tidak bisa dihapus.');

        try {
            $deletion->handle($target);
        } catch (DisplayException $e) {
            return back()->with('ap_err', $e->getMessage());
        } catch (\Throwable $e) {
            report($e);

            return back()->with('ap_err', 'Gagal menghapus user. Hapus dulu server miliknya.');
        }

        return $this->ok('User ' . $target->username . ' dihapus.');
    }

    public function toggleSuspend(Request $request, SuspensionService $suspension, int $id)
    {
        $this->superadmin($request);
        $server = Server::query()->findOrFail($id);
        $unsuspend = $server->isSuspended();

        try {
            $suspension->toggle($server, $unsuspend ? SuspensionService::ACTION_UNSUSPEND : SuspensionService::ACTION_SUSPEND);
        } catch (\Throwable $e) {
            report($e);

            return back()->with('ap_err', 'Gagal mengubah status server.');
        }

        return $this->ok('Server ' . $server->name . ($unsuspend ? ' diaktifkan lagi.' : ' disuspend.'));
    }

    public function deleteServer(Request $request, ServerDeletionService $deletion, int $id)
    {
        $this->superadmin($request);
        $server = Server::query()->findOrFail($id);

        try {
            $deletion->handle($server);
        } catch (\Throwable $e) {
            report($e);

            return back()->with('ap_err', 'Gagal menghapus server (cek koneksi ke Wings).');
        }

        return $this->ok('Server ' . $server->name . ' dihapus.');
    }

    private function superadmin(Request $request): User
    {
        $me = $request->user();
        abort_unless(AntiPeep::isSuperadmin($me), 403);

        return $me;
    }

    private function ok(string $message)
    {
        return redirect()->route('antipeep.index')->with('ap_ok', $message);
    }
}
