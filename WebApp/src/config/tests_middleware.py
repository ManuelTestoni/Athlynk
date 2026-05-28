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


class _Ok:
    status_code = 200
