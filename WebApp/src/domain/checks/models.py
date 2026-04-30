from django.db import models

class QuestionnaireTemplate(models.Model):
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='questionnaire_templates')
    title = models.CharField(max_length=200)
    description = models.TextField(null=True, blank=True)
    questionnaire_type = models.CharField(max_length=50)
    frequency_type = models.CharField(max_length=50, null=True, blank=True)
    phase = models.CharField(max_length=100, null=True, blank=True)
    objective = models.CharField(max_length=200, null=True, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.title

class QuestionnaireResponse(models.Model):
    questionnaire_template = models.ForeignKey(QuestionnaireTemplate, on_delete=models.CASCADE, related_name='responses')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='questionnaire_responses')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='received_questionnaire_responses')
    submitted_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=50)
    weight_kg = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    body_circumferences = models.JSONField(null=True, blank=True)
    skinfolds = models.JSONField(null=True, blank=True)
    limitations = models.TextField(null=True, blank=True)
    injuries = models.TextField(null=True, blank=True)
    notes = models.TextField(null=True, blank=True)
    answers_json = models.JSONField(null=True, blank=True)
    coach_feedback = models.TextField(null=True, blank=True)
    coach_private_notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Response to {self.questionnaire_template} by {self.client}"

class ProgressPhoto(models.Model):
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='progress_photos')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='client_progress_photos')
    questionnaire_response = models.ForeignKey(QuestionnaireResponse, on_delete=models.SET_NULL, null=True, blank=True, related_name='photos')
    file_url = models.URLField(max_length=500)
    photo_type = models.CharField(max_length=50)
    captured_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.photo_type} Photo for {self.client}"
