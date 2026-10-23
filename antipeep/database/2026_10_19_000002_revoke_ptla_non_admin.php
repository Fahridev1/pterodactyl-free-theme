<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        // PTLA (key_type 2 = application) hanya untuk admin ke atas: cabut milik akun non-admin.
        DB::table('api_keys')
            ->where('key_type', 2)
            ->whereIn('user_id', DB::table('users')->where('root_admin', 0)->select('id'))
            ->delete();
    }

    public function down(): void
    {
        // Key yang sudah dicabut tidak bisa dikembalikan.
    }
};
