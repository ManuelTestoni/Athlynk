"""Tests for the security hardening: password policy, upload sniffing,
form-input sanitization."""
import io

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import RequestFactory, TestCase

from config.middleware import SanitizationMiddleware
from config.services import uploads
from config.services.images import is_image
from config.services.sanitize import InvalidInput, validate_password_strength


def _png_bytes():
    from PIL import Image
    buf = io.BytesIO()
    Image.new('RGB', (8, 8), (123, 222, 64)).save(buf, format='PNG')
    return buf.getvalue()


class PasswordPolicyTests(TestCase):
    def test_accepts_strong(self):
        self.assertEqual(validate_password_strength('V0lt!Athlynk#9'), 'V0lt!Athlynk#9')

    def test_rejects_too_short(self):
        with self.assertRaises(InvalidInput):
            validate_password_strength('V0lt!A#9')  # 8 chars, < 12

    def test_requires_each_class(self):
        for pw in ('alllowercase1!aa', 'ALLUPPERCASE1!AA', 'NoDigitsHere!!aa', 'NoSymbol12345Aa'):
            with self.assertRaises(InvalidInput):
                validate_password_strength(pw)

    def test_rejects_similar_to_email(self):
        with self.assertRaises(InvalidInput):
            validate_password_strength('Marcorossi12!x', email='marcorossi@x.com')


class UploadSniffTests(TestCase):
    def test_real_png_is_image(self):
        f = SimpleUploadedFile('x.jpg', _png_bytes(), content_type='image/jpeg')
        self.assertTrue(is_image(f))

    def test_disguised_payload_rejected(self):
        # Executable/script bytes renamed to .jpg must not pass as an image.
        f = SimpleUploadedFile('evil.jpg', b'#!/bin/sh\nrm -rf /\n', content_type='image/jpeg')
        self.assertFalse(is_image(f))

    def test_video_signature(self):
        mp4 = b'\x00\x00\x00\x18ftypmp42' + b'\x00' * 16
        self.assertTrue(uploads.looks_like_video(io.BytesIO(mp4)))
        self.assertFalse(uploads.looks_like_video(io.BytesIO(b'not a video at all')))

    def test_safe_filename_strips_path(self):
        self.assertEqual(uploads.safe_filename('../../etc/passwd'), 'passwd.mp4')
        self.assertEqual(uploads.safe_filename('a b/c$d.MOV'), 'c-d.mov')

    def test_store_attachment_rejects_junk(self):
        f = SimpleUploadedFile('evil.mp4', b'<html>nope</html>', content_type='video/mp4')
        saved, kind = uploads.store_attachment(f, dir_prefix='t/')
        self.assertIsNone(saved)
        self.assertIsNone(kind)


class CustomExerciseSanitizeTests(TestCase):
    """Custom-exercise free-text fields: cap lengths (see views_workouts_taxonomy)."""

    def test_notes_caps(self):
        from domain.workouts.models import Exercise
        from config.views_workouts_taxonomy import _exercise_payload_apply

        class _Coach:  # minimal stand-in; only .id is read for the slug
            id = 1
        ex = Exercise(is_custom=True)
        _exercise_payload_apply(ex, {
            'name': 'Test',
            'coach_notes': 'n' * 9000,                  # capped to 5000
            'description': 'd' * 9000,                   # capped to 5000
        }, _Coach())
        self.assertEqual(len(ex.coach_notes), 5000)
        self.assertEqual(len(ex.description), 5000)


class FormSanitizeTests(TestCase):
    def test_strips_control_chars_keeps_password(self):
        rf = RequestFactory()
        req = rf.post('/x/', {'note': 'a\x07b\x00c', 'password': 'pa\x07ss\x00word'})
        SanitizationMiddleware(lambda r: r)(req)
        # Control chars stripped from normal field...
        self.assertEqual(req.POST['note'], 'abc')
        # ...but a password keeps everything except the null byte.
        self.assertEqual(req.POST['password'], 'pa\x07ssword')
