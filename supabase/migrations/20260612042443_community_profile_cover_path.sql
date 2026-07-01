alter table public.profiles
add column if not exists cover_path text;

drop policy if exists "community_images_insert_profile_cover_namespace" on storage.objects;
create policy "community_images_insert_profile_cover_namespace"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'profile-covers'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_update_profile_cover_namespace" on storage.objects;
create policy "community_images_update_profile_cover_namespace"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'profile-covers'
  and public.can_use_profile_path((storage.foldername(name))[2])
)
with check (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'profile-covers'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

drop policy if exists "community_images_delete_profile_cover_namespace" on storage.objects;
create policy "community_images_delete_profile_cover_namespace"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'community-images'
  and (storage.foldername(name))[1] = 'profile-covers'
  and public.can_use_profile_path((storage.foldername(name))[2])
);

select pg_notify('pgrst', 'reload schema');
