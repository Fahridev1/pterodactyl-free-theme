<?php

namespace Pterodactyl\AntiPeep;

use Illuminate\Support\Facades\DB;
use Pterodactyl\Models\ApiKey;
use Pterodactyl\Models\User;

/**
 * Pusat aturan role & mode Anti-Intip.
 */
class AntiPeep
{
    public const SETTING_KEY = 'settings::antipeep:mode';
    public const ROLES = ['superadmin', 'admin', 'reseller', 'user'];

    private static ?bool $cache = null;

    /** anti_peep_mode. Kalau setting belum ada atau DB error: anggap NYALA (aman). */
    public static function enabled(): bool
    {
        if (self::$cache !== null) {
            return self::$cache;
        }
        try {
            $value = DB::table('settings')->where('key', self::SETTING_KEY)->value('value');
            self::$cache = $value === null ? true : filter_var($value, FILTER_VALIDATE_BOOLEAN);
        } catch (\Throwable $e) {
            self::$cache = true;
        }

        return self::$cache;
    }

    public static function setEnabled(bool $on): void
    {
        DB::table('settings')->updateOrInsert(
            ['key' => self::SETTING_KEY],
            ['value' => $on ? 'true' : 'false']
        );
        self::$cache = $on;
    }

    /** Role efektif. Superadmin = HANYA user ID 1. */
    public static function role(User $user): string
    {
        if ((int) $user->id === 1) {
            return 'superadmin';
        }
        $role = (string) $user->getAttribute('role');
        if ($role === 'superadmin' || !in_array($role, self::ROLES, true)) {
            $role = $user->root_admin ? 'admin' : 'user';
        }

        return $role;
    }

    public static function isSuperadmin(User $user): bool
    {
        return (int) $user->id === 1;
    }

    /** Role yang boleh DIBUAT oleh $actor. */
    public static function creatableRoles(User $actor): array
    {
        switch (self::role($actor)) {
            case 'superadmin':
                return ['admin', 'reseller', 'user'];
            case 'admin':
                return ['reseller', 'user'];
            case 'reseller':
                return ['user'];
            default:
                return [];
        }
    }

    public static function canCreate(User $actor, string $role): bool
    {
        return in_array($role, self::creatableRoles($actor), true);
    }

    /** Boleh mengubah/menghapus akun $target? */
    public static function canManage(User $actor, User $target): bool
    {
        if (self::isSuperadmin($actor) || (int) $actor->id === (int) $target->id) {
            return true;
        }
        $targetRole = self::role($target);
        switch (self::role($actor)) {
            case 'admin':
                return in_array($targetRole, ['reseller', 'user'], true);
            case 'reseller':
                return $targetRole === 'user' && (int) $target->getAttribute('created_by') === (int) $actor->id;
            default:
                return false;
        }
    }

    /** Tingkat role: superadmin 4, admin 3, reseller 2, user 1. */
    public static function rank(string $role): int
    {
        $map = ['superadmin' => 4, 'admin' => 3, 'reseller' => 2, 'user' => 1];

        return $map[$role] ?? 0;
    }

    /** Hapus semua API key tipe aplikasi (PTLA) milik user. */
    public static function revokeApplicationKeys(int $userId): void
    {
        DB::table('api_keys')->where('user_id', $userId)->where('key_type', ApiKey::TYPE_APPLICATION)->delete();
    }

    /** Ubah role (dipakai Superadmin). Role admin = root_admin 1; selain itu root_admin 0 dan PTLA dicabut. */
    public static function setRole(User $user, string $role): void
    {
        if ((int) $user->id === 1 || !in_array($role, ['admin', 'reseller', 'user'], true)) {
            return;
        }
        DB::table('users')->where('id', $user->id)->update([
            'role' => $role,
            'root_admin' => $role === 'admin' ? 1 : 0,
        ]);
        if ($role !== 'admin') {
            self::revokeApplicationKeys((int) $user->id);
        }
    }
}
