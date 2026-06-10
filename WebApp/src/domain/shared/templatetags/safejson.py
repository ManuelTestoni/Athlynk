"""Filtro per iniettare JSON pre-serializzato dentro blocchi <script>.

`{{ x_json|safe }}` è vulnerabile: una stringa contenente "</script>" chiude
il blocco script (stored XSS, es. coach → atleta via label di una domanda).
`json_js` escapa "<" come \\u003c — valido sia in JSON che in JS — prima di
marcare il valore safe. Stessa tecnica del builtin |json_script, ma applicabile
al JSON già serializzato nelle view senza cambiare il protocollo dei template.
"""

from django import template
from django.utils.safestring import mark_safe

register = template.Library()


@register.filter(name='json_js')
def json_js(value):
    # ' copre anche l'uso dentro attributi Alpine single-quoted
    # (es. @click='... {{ x|json_js }} ...'); entrambi gli escape sono
    # JSON valido perché ' e < compaiono solo dentro stringhe.
    return mark_safe(str(value).replace('<', '\\u003c').replace("'", '\\u0027'))
