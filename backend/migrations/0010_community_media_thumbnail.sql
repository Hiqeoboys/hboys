-- Simpan URL thumbnail WebP video komunitas (diunggah ke Cloudflare R2)
-- agar cover video langsung tampil tanpa kotak hitam saat chat dibuka ulang.
alter table if exists public.community_messages
  add column if not exists media_thumbnail_url text;
