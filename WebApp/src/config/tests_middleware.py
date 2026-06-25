from django.test import SimpleTestCase, RequestFactory

from config.middleware import SanitizationMiddleware


class SanitizationMiddlewareTest(SimpleTestCase):
    def setUp(self):
        self.rf = RequestFactory()
        self.mw = SanitizationMiddleware(lambda r: _Ok())

    def test_chat_send_allows_multipart(self):
        # Regression: chat send posts multipart (text + optional attachment).
        # The JSON gate must not reject it with 415.
        request = self.rf.post(
            '/api/chat/1/send/',
            data={'body': 'ciao'},
        )
        response = self.mw(request)
        self.assertEqual(response.status_code, 200)

    def test_other_api_rejects_form_post(self):
        request = self.rf.post(
            '/api/allenamenti/save/',
            data={'title': 'x'},
        )
        response = self.mw(request)
        self.assertEqual(response.status_code, 415)

    def test_profile_photo_allows_multipart(self):
        # Regression: avatar upload is multipart; the JSON gate used to 415 it.
        for path in ('/api/v1/profile/photo', '/api/v1/coach/profile/photo'):
            request = self.rf.post(path, data={'photo': 'x'})
            self.assertEqual(self.mw(request).status_code, 200, path)

    def test_check_submit_allows_multipart(self):
        request = self.rf.post('/api/v1/checks/5/submit', data={'answers': '{}'})
        self.assertEqual(self.mw(request).status_code, 200)

    def test_large_multipart_import_not_capped(self):
        # A >1 MB import upload must reach the view (its own size cap), not get a
        # 413 from the JSON body cap. Real oversized body so CONTENT_LENGTH is set
        # by the test client.
        from django.core.files.uploadedfile import SimpleUploadedFile
        big = SimpleUploadedFile('plan.pdf', b'%PDF-' + b'0' * (1024 * 1024 + 10),
                                 content_type='application/pdf')
        request = self.rf.post('/api/allenamenti/import/pdf/', data={'file': big})
        self.assertEqual(self.mw(request).status_code, 200)

    def test_large_json_body_still_capped(self):
        request = self.rf.post(
            '/api/v1/something', data='{}', content_type='application/json',
            CONTENT_LENGTH=str(2 * 1024 * 1024),
        )
        self.assertEqual(self.mw(request).status_code, 413)


class _Ok:
    status_code = 200
