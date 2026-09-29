open_file_cache off;
if (-f /etc/nginx/mantenimiento/mapalab) {
    rewrite ^ /__mantenimiento/mapalab last;
}
