<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasColumn('users', 'role')) {
            Schema::table('users', function (Blueprint $table) {
                $table->string('role', 20)->default('user')->after('root_admin');
            });
        }
        if (!Schema::hasColumn('users', 'created_by')) {
            Schema::table('users', function (Blueprint $table) {
                $table->unsignedInteger('created_by')->nullable()->after('role');
            });
        }

        // Isi awal role dari data yang sudah ada. Hanya ID 1 yang jadi superadmin.
        DB::table('users')->where('root_admin', 1)->update(['role' => 'admin']);
        DB::table('users')->where('root_admin', 0)->update(['role' => 'user']);
        DB::table('users')->where('id', 1)->update(['role' => 'superadmin']);

        // Setting global anti_peep_mode, default NYALA. Tidak menimpa kalau sudah ada.
        if (!DB::table('settings')->where('key', 'settings::antipeep:mode')->exists()) {
            DB::table('settings')->insert(['key' => 'settings::antipeep:mode', 'value' => 'true']);
        }
    }

    public function down(): void
    {
        DB::table('settings')->where('key', 'settings::antipeep:mode')->delete();
        Schema::table('users', function (Blueprint $table) {
            if (Schema::hasColumn('users', 'created_by')) {
                $table->dropColumn('created_by');
            }
            if (Schema::hasColumn('users', 'role')) {
                $table->dropColumn('role');
            }
        });
    }
};
