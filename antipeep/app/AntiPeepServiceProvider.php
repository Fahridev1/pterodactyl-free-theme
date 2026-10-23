<?php

namespace Pterodactyl\AntiPeep;

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\ServiceProvider;
use Pterodactyl\Models\User;

class AntiPeepServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // 1. Guard role + Anti-Intip + PTLA, dipasang di akhir tiap grup (setelah login & binding).
        $router = $this->app['router'];
        foreach (['web', 'client-api', 'application-api'] as $group) {
            $router->pushMiddlewareToGroup($group, AntiPeepGuard::class);
        }

        // 2. Role selalu searah dengan root_admin; turun dari admin = PTLA dicabut.
        User::saving(function (User $user) {
            static $ready = null;
            $ready = $ready ?? $this->roleColumnExists();
            if (!$ready || (int) $user->id === 1) {
                return;
            }
            $role = (string) $user->getAttribute('role');
            if ($user->root_admin && $role !== 'admin') {
                $user->setAttribute('role', 'admin');
            } elseif (!$user->root_admin && $role === 'admin') {
                $user->setAttribute('role', 'user');
            }
            if ($user->exists && $user->isDirty('root_admin') && !$user->root_admin) {
                AntiPeep::revokeApplicationKeys((int) $user->id);
            }
        });

        // 3. Halaman manajemen (dipakai semua role; isi menyesuaikan role).
        $this->loadViewsFrom(__DIR__ . '/../../resources/views/antipeep', 'antipeep');
        Route::middleware(['web', 'auth'])->prefix('admin/antipeep')->group(function () {
            Route::get('/', [AntiPeepController::class, 'index'])->name('antipeep.index');
            Route::post('/toggle', [AntiPeepController::class, 'toggle'])->name('antipeep.toggle');
            Route::post('/users', [AntiPeepController::class, 'storeUser'])->name('antipeep.users.store');
            // Kontrol Superadmin
            Route::post('/users/{id}/role', [AntiPeepController::class, 'setRole'])->whereNumber('id')->name('antipeep.users.role');
            Route::post('/users/{id}/delete', [AntiPeepController::class, 'deleteUser'])->whereNumber('id')->name('antipeep.users.delete');
            Route::post('/servers/{id}/suspend', [AntiPeepController::class, 'toggleSuspend'])->whereNumber('id')->name('antipeep.servers.suspend');
            Route::post('/servers/{id}/delete', [AntiPeepController::class, 'deleteServer'])->whereNumber('id')->name('antipeep.servers.delete');
        });
    }

    private function roleColumnExists(): bool
    {
        try {
            return Schema::hasColumn('users', 'role');
        } catch (\Throwable $e) {
            return false;
        }
    }
}
