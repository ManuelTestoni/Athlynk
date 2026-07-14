"""Per-user branding: hex -> CSS rgb-triplet conversion (Impostazioni → Aspetto)."""
from django.contrib.auth.hashers import make_password
from django.test import SimpleTestCase, TestCase, override_settings

from domain.accounts.models import User, CoachProfile

from .session_utils import _rgb_triplet, _shade, BRAND_DEFAULT_PRIMARY

LOCMEM = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}


class BrandColorHelpersTests(SimpleTestCase):
    def test_rgb_triplet_converts_hex(self):
        self.assertEqual(_rgb_triplet('#1E3A5F'), '30 58 95')

    def test_rgb_triplet_invalid_hex_falls_back_to_default(self):
        self.assertEqual(_rgb_triplet('not-a-color'), _rgb_triplet(BRAND_DEFAULT_PRIMARY))
        self.assertEqual(_rgb_triplet(''), _rgb_triplet(BRAND_DEFAULT_PRIMARY))
        self.assertEqual(_rgb_triplet('#GGGGGG'), _rgb_triplet(BRAND_DEFAULT_PRIMARY))

    def test_shade_darkens_and_stays_in_range(self):
        r, g, b = (int(x) for x in _shade('#1E3A5F', 0.72).split())
        self.assertEqual((r, g, b), (22, 42, 68))
        for v in (r, g, b):
            self.assertTrue(0 <= v <= 255)

    def test_shade_invalid_hex_falls_back_to_default(self):
        self.assertEqual(_shade('bogus'), _shade(BRAND_DEFAULT_PRIMARY))


@override_settings(CACHES=LOCMEM)
class BrandSettingsViewTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(email='co@e.com', password_hash=make_password('x'),
                                        role='COACH', is_verified=True)
        CoachProfile.objects.create(user=self.user, first_name='C', last_name='O',
                                    professional_type='COACH')
        session = self.client.session
        session['user_id'] = self.user.id
        session.save()

    def _post(self, **fields):
        data = {'action': 'aspetto', 'brand_name': '', 'brand_primary': '', 'brand_accent': '', **fields}
        return self.client.post('/impostazioni/', data)

    def test_saves_valid_brand(self):
        r = self._post(brand_name='Studio X', brand_primary='#7A2E2E', brand_accent='#C08A3E')
        self.assertEqual(r.status_code, 302)
        self.user.refresh_from_db()
        self.assertEqual(self.user.brand_name, 'Studio X')
        self.assertEqual(self.user.brand_primary, '#7A2E2E')
        self.assertEqual(self.user.brand_accent, '#C08A3E')

    def test_rejects_invalid_hex_and_does_not_save(self):
        r = self._post(brand_primary='javascript:alert(1)')
        self.assertEqual(r.status_code, 200)  # re-renders with error, no redirect
        self.user.refresh_from_db()
        self.assertEqual(self.user.brand_primary, '')

    def test_reset_clears_all_fields(self):
        self._post(brand_name='Studio X', brand_primary='#7A2E2E', brand_accent='#C08A3E')
        r = self.client.post('/impostazioni/', {'action': 'aspetto', 'reset': '1'})
        self.assertEqual(r.status_code, 302)
        self.user.refresh_from_db()
        self.assertEqual(self.user.brand_name, '')
        self.assertEqual(self.user.brand_primary, '')
        self.assertEqual(self.user.brand_accent, '')
