"""SEO + AI discoverability: robots.txt, sitemap.xml, llms.txt.

Athlynk è quasi interamente dietro autenticazione: le uniche pagine indicizzabili
sono auth e legali. Tutto il resto è esplicitamente escluso dai crawler.
"""
from django.conf import settings
from django.http import HttpResponse
from django.urls import reverse

# Pagine pubbliche indicizzabili (name, changefreq, priority)
PUBLIC_PAGES = [
    ('login', 'monthly', '1.0'),
    ('signup', 'monthly', '0.9'),
    ('ai_transparency', 'monthly', '0.6'),
    ('privacy', 'monthly', '0.5'),
    ('cookie_policy', 'monthly', '0.5'),
]


def robots_txt(request):
    site = settings.SITE_URL.rstrip('/')
    allowed = '\n'.join(f'Allow: {reverse(name)}' for name, _, _ in PUBLIC_PAGES)
    body = f"""# Athlynk — robots.txt
# Piattaforma per coach e atleti. Solo le pagine pubbliche sono indicizzabili.

User-agent: *
{allowed}
Allow: /llms.txt
Disallow: /

Sitemap: {site}/sitemap.xml
"""
    return HttpResponse(body, content_type='text/plain; charset=utf-8')


def sitemap_xml(request):
    site = settings.SITE_URL.rstrip('/')
    entries = ''.join(
        f"""  <url>
    <loc>{site}{reverse(name)}</loc>
    <changefreq>{changefreq}</changefreq>
    <priority>{priority}</priority>
  </url>
"""
        for name, changefreq, priority in PUBLIC_PAGES
    )
    body = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f'{entries}</urlset>\n'
    )
    return HttpResponse(body, content_type='application/xml; charset=utf-8')


def llms_txt(request):
    """llms.txt — descrizione del servizio per crawler e motori di ricerca AI."""
    site = settings.SITE_URL.rstrip('/')
    body = f"""# Athlynk

> Athlynk è la piattaforma italiana per coach, personal trainer e nutrizionisti
> che gestiscono i propri atleti online: schede di allenamento con progressioni,
> piani nutrizionali con tracking dei macro, check di avanzamento con foto e
> misure, chat coach-atleta, agenda appuntamenti e abbonamenti. Include CHIRON,
> un assistente AI per domande su allenamento e nutrizione, e l'importazione
> automatica di diete e schede da PDF/Excel tramite modelli GPT-OSS.

Athlynk serve due ruoli:
- Coach (personal trainer, preparatori, nutrizionisti): creano e assegnano
  schede di allenamento e piani alimentari, monitorano i progressi dei clienti,
  gestiscono check periodici, agenda e abbonamenti.
- Atleti: seguono i piani assegnati, registrano allenamenti (carichi, serie,
  RPE) e pasti, inviano check con foto e misure, comunicano col proprio coach.
  Disponibile anche app iOS.

## Pagine

- [Accesso]({site}/login/): login per coach e atleti
- [Registrazione]({site}/registrati/): crea un account coach o atleta
- [Trasparenza AI]({site}/ai-trasparenza/): come Athlynk usa l'intelligenza artificiale (AI Act, Reg. UE 2024/1689)
- [Privacy Policy]({site}/privacy/): informativa sul trattamento dei dati (GDPR)
- [Cookie Policy]({site}/cookie/): cookie e tecnologie utilizzate

## Note

- Lingua principale: italiano.
- L'area applicativa è riservata agli utenti registrati e non è indicizzabile.
- L'AI organizza informazioni e assiste; piani e valutazioni sono sempre
  decisi da coach umani. Nessun consiglio medico.
"""
    return HttpResponse(body, content_type='text/plain; charset=utf-8')
