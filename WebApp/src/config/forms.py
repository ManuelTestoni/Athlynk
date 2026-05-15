from django import forms
from domain.billing.models import SubscriptionPlan


class SubscriptionPlanForm(forms.ModelForm):
    """Form per creare e modificare piani di abbonamento"""
    
    class Meta:
        model = SubscriptionPlan
        fields = [
            'name',
            'plan_type',
            'description',
            'price',
            'currency',
            'duration_days',
            'billing_interval',
            'is_active',
        ]
        widgets = {
            'name': forms.TextInput(attrs={
                'class': 'al-input',
                'placeholder': 'Es. Piano Base',
                'required': True,
            }),
            'plan_type': forms.TextInput(attrs={
                'class': 'al-input',
                'placeholder': 'Es. Mensile, Trimestrale, Annuale',
                'required': True,
            }),
            'description': forms.Textarea(attrs={
                'class': 'al-textarea',
                'placeholder': 'Descrizione del piano…',
                'rows': 3,
            }),
            'price': forms.NumberInput(attrs={
                'class': 'al-input',
                'placeholder': 'Es. 29.99',
                'step': '0.01',
                'required': True,
            }),
            'currency': forms.TextInput(attrs={
                'class': 'al-input',
                'value': 'EUR',
            }),
            'duration_days': forms.NumberInput(attrs={
                'class': 'al-input',
                'placeholder': 'Es. 30 per mensile, 90 per trimestrale',
            }),
            'billing_interval': forms.TextInput(attrs={
                'class': 'al-input',
                'placeholder': 'Es. monthly, quarterly, yearly',
            }),
            'is_active': forms.CheckboxInput(attrs={
                'style': 'width:18px;height:18px;accent-color:var(--al-bronze);cursor:pointer;',
            }),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['description'].required = False
        self.fields['duration_days'].required = False
        self.fields['billing_interval'].required = False
        
        # Labels in italiano
        self.fields['name'].label = 'Nome Piano'
        self.fields['plan_type'].label = 'Tipo Piano'
        self.fields['description'].label = 'Descrizione'
        self.fields['price'].label = 'Prezzo'
        self.fields['currency'].label = 'Valuta'
        self.fields['duration_days'].label = 'Durata (giorni)'
        self.fields['billing_interval'].label = 'Intervallo Fatturazione'
        self.fields['is_active'].label = 'Piano Attivo'
