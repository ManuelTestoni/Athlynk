from pathlib import Path

from rcssmin import cssmin
from rjsmin import jsmin
from whitenoise.storage import CompressedStaticFilesStorage


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
