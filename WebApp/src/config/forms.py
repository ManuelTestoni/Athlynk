from django import forms
from domain.billing.models import Bundle, BundleItem, SubscriptionPlan


class SubscriptionPlanForm(forms.ModelForm):
    """Form per creare e modificare piani di abbonamento"""

    class Meta:
        model = SubscriptionPlan
        fields = [
            'name',
            'plan_type',
            'kind',
            'description',
            'price',
            'currency',
            'duration_days',
            'billing_interval',
            'is_active',
        ]
        widgets = {
            'kind': forms.Select(attrs={
                'class': 'al-select',
                'x-model': 'kind',
            }),
            'name': forms.TextInput(attrs={
                'class': 'al-input',
                'placeholder': 'Es. Piano Base',
                'required': True,
            }),
            'plan_type': forms.Select(attrs={
                'class': 'al-select',
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
            'currency': forms.Select(attrs={
                'class': 'al-select',
            }),
            'duration_days': forms.NumberInput(attrs={
                'class': 'al-input',
                'placeholder': 'Es. 30 per mensile, 90 per trimestrale',
            }),
            'billing_interval': forms.Select(attrs={
                'class': 'al-select',
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
        self.fields['kind'].label = 'Tipologia'
        self.fields['description'].label = 'Descrizione'
        self.fields['price'].label = 'Prezzo'
        self.fields['currency'].label = 'Valuta'
        self.fields['duration_days'].label = 'Durata (giorni)'
        self.fields['billing_interval'].label = 'Intervallo Fatturazione'
        self.fields['is_active'].label = 'Piano Attivo'


class BundleForm(forms.ModelForm):
    """Form per creare e modificare pacchetti (bundle)."""

    class Meta:
        model = Bundle
        fields = ['name', 'description', 'discount_percent', 'discount_amount', 'currency', 'is_active']
        widgets = {
            'name': forms.TextInput(attrs={'class': 'al-input', 'placeholder': 'Es. Pacchetto Trasformazione', 'required': True}),
            'description': forms.Textarea(attrs={'class': 'al-textarea', 'placeholder': 'Descrizione del pacchetto…', 'rows': 3}),
            'discount_percent': forms.NumberInput(attrs={'class': 'al-input', 'placeholder': 'Es. 10', 'step': '0.01'}),
            'discount_amount': forms.NumberInput(attrs={'class': 'al-input', 'placeholder': 'Es. 20.00', 'step': '0.01'}),
            'currency': forms.Select(attrs={'class': 'al-select'}),
            'is_active': forms.CheckboxInput(attrs={
                'style': 'width:18px;height:18px;accent-color:var(--al-bronze);cursor:pointer;',
            }),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['description'].required = False
        self.fields['discount_percent'].required = False
        self.fields['discount_amount'].required = False
        self.fields['name'].label = 'Nome Pacchetto'
        self.fields['description'].label = 'Descrizione'
        self.fields['discount_percent'].label = 'Sconto (%)'
        self.fields['discount_amount'].label = 'Sconto (importo fisso)'
        self.fields['currency'].label = 'Valuta'
        self.fields['is_active'].label = 'Pacchetto Attivo'


class BundleItemForm(forms.ModelForm):
    class Meta:
        model = BundleItem
        fields = ['plan', 'quantity', 'price_override']
        widgets = {
            'plan': forms.Select(attrs={'class': 'al-select'}),
            'quantity': forms.NumberInput(attrs={'class': 'al-input', 'min': '1'}),
            'price_override': forms.NumberInput(attrs={'class': 'al-input', 'placeholder': 'Opzionale', 'step': '0.01'}),
        }

    def __init__(self, *args, coach=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['price_override'].required = False
        qs = SubscriptionPlan.objects.filter(kind=SubscriptionPlan.KIND_ONE_TIME, is_active=True)
        if coach is not None:
            qs = qs.filter(coach=coach)
        self.fields['plan'].queryset = qs.order_by('name')


BundleItemFormSet = forms.inlineformset_factory(
    Bundle, BundleItem,
    form=BundleItemForm,
    extra=1, can_delete=True,
)
