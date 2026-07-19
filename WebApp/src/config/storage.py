from pathlib import Path

from django.core.cache import cache
from rcssmin import cssmin
from rjsmin import jsmin
from storages.backends.s3 import S3Storage
from whitenoise.storage import CompressedStaticFilesStorage

from .services import cachekeys


class MinifiedCompressedStaticFilesStorage(CompressedStaticFilesStorage):
    """Minifies .css/.js in place at collectstatic time, before whitenoise
    gzip/brotli-compresses them. Runs once at deploy time, not per-request."""

    def post_process(self, paths, dry_run=False, **options):
        if not dry_run:
            for name in paths:
                if name.endswith('.css'):
                    self._minify(name, cssmin)
                elif name.endswith('.js'):
                    self._minify(name, jsmin)
        yield from super().post_process(paths, dry_run, **options)

    def _minify(self, name, minifier):
        full_path = Path(self.path(name))
        full_path.write_text(minifier(full_path.read_text(encoding='utf-8')), encoding='utf-8')


class CachedSignedS3Storage(S3Storage):
    """S3Storage whose .url() caches the signed URL per storage key.

    Without this, every .url() call (templates, JSON serializers, often in
    loops over exercise/media rows) re-signs the URL: per-row CPU cost and a
    *different* URL string on every response, which defeats browser/URLSession
    image caching entirely. Caching the string keeps it stable for ~50 min so
    clients can finally cache the underlying bytes.

    TTL is derived from querystring_expire minus a 10-minute safety margin, so
    a cached URL always has ample remaining signature lifetime. No
    invalidation needed: file_overwrite=False guarantees a key's content never
    changes once written.
    """

    def url(self, name, parameters=None, expire=None, http_method=None):
        if parameters or expire or http_method or not self.querystring_auth:
            return super().url(name, parameters=parameters, expire=expire,
                               http_method=http_method)
        key = cachekeys.media_url(name)
        cached = cache.get(key)
        if cached:
            return cached
        signed = super().url(name)
        cache.set(key, signed, max(self.querystring_expire - 600, 60))
        return signed
