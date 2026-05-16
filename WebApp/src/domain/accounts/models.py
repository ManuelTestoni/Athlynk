from django.db import models

class User(models.Model):
    email = models.EmailField(unique=True)
    password_hash = models.CharField(max_length=255)
    role = models.CharField(max_length=50)
    is_active = models.BooleanField(default=True)
    is_verified = models.BooleanField(default=False)
    email_verification_token = models.CharField(max_length=128, blank=True, default='')
    email_verification_sent_at = models.DateTimeField(null=True, blank=True)
    last_login_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.email

class CoachProfile(models.Model):
    PROFESSIONAL_TYPES = [
        ('COACH', 'Coach (Allenamento + Nutrizione)'),
        ('ALLENATORE', 'Allenatore'),
        ('NUTRIZIONISTA', 'Nutrizionista'),
    ]

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='coach_profile')
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100)
    phone = models.CharField(max_length=20, null=True, blank=True)
    birth_date = models.DateField(null=True, blank=True)
    gender = models.CharField(max_length=20, null=True, blank=True)
    bio = models.TextField(null=True, blank=True)
    description = models.TextField(null=True, blank=True)
    profile_image_url = models.URLField(max_length=500, null=True, blank=True)
    specialization = models.CharField(max_length=200, null=True, blank=True)
    certifications = models.TextField(null=True, blank=True)
    years_experience = models.IntegerField(null=True, blank=True)
    city = models.CharField(max_length=100, null=True, blank=True)
    professional_type = models.CharField(max_length=20, choices=PROFESSIONAL_TYPES, default='COACH')
    profile_image = models.FileField(upload_to='coach_photos/', null=True, blank=True)
    social_instagram = models.URLField(max_length=300, null=True, blank=True)
    social_youtube = models.URLField(max_length=300, null=True, blank=True)
    social_tiktok = models.URLField(max_length=300, null=True, blank=True)
    social_facebook = models.URLField(max_length=300, null=True, blank=True)
    social_website = models.URLField(max_length=300, null=True, blank=True)
    professional_videos = models.TextField(null=True, blank=True)
    platform_subscription_status = models.CharField(max_length=50)
    is_platform_subscription_active = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Coach: {self.first_name} {self.last_name}"

class ClientProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='client_profile')
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100)
    phone = models.CharField(max_length=20, null=True, blank=True)
    birth_date = models.DateField(null=True, blank=True)
    gender = models.CharField(max_length=20, null=True, blank=True)
    height_cm = models.IntegerField(null=True, blank=True)
    activity_level = models.CharField(max_length=100, null=True, blank=True)
    medical_notes_summary = models.TextField(null=True, blank=True)
    primary_goal = models.CharField(max_length=200, null=True, blank=True)
    payment_status_summary = models.CharField(max_length=100, null=True, blank=True)
    onboarding_status = models.CharField(max_length=100, null=True, blank=True)
    client_status = models.CharField(max_length=100, null=True, blank=True)
    profile_image = models.FileField(upload_to='client_photos/', null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Client: {self.first_name} {self.last_name}"


class PasswordResetToken(models.Model):
    """Single-use, short-lived password-reset token.

    The plaintext token is only ever shown to the user via email link;
    the database stores the SHA-256 hash of the token to neutralise DB leaks.
    """
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='password_reset_tokens')
    token_hash = models.CharField(max_length=64, unique=True, db_index=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    request_ip = models.GenericIPAddressField(null=True, blank=True)
    request_user_agent = models.CharField(max_length=512, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['user', 'used_at']),
            models.Index(fields=['expires_at']),
        ]

    def __str__(self):
        return f"ResetToken(user={self.user_id}, used={self.used_at is not None})"
