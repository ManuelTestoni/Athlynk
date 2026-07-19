"""Ranking and query construction for the literature search.

Europe PMC is stubbed: these tests pin the judgement calls the module makes, not
the API's current contents. The two that matter most are the ones that caused
visibly wrong answers during development — citation-sorted search losing
relevance entirely, and strict term ANDing returning nothing.
"""

from unittest.mock import patch

from django.test import SimpleTestCase

from chiron import scientific_search as ss


def _record(title, year=2020, citations=10, journal='Sports medicine',
            doi=None, authors='Rossi M, Bianchi L', abstract='Abstract.'):
    return {
        'title': title,
        'pubYear': str(year),
        'citedByCount': citations,
        'journalInfo': {'journal': {'title': journal}},
        'doi': doi or f'10.0000/{abs(hash(title)) % 100000}',
        'authorString': authors,
        'abstractText': abstract,
        'id': str(abs(hash(title)) % 100000),
        'source': 'MED',
    }


class TermExtractionTests(SimpleTestCase):
    def test_drops_stopwords_and_short_tokens(self):
        self.assertEqual(
            ss._terms('how much protein per kg for hypertrophy'),
            ['hypertrophy', 'protein'],
        )

    def test_clauses_relax_progressively(self):
        clauses = ss._term_clauses('creatine supplementation kidney function')
        self.assertGreater(len(clauses), 1)
        # Strictest first, and every term is scoped to title/abstract — a bare
        # free-text query is an implicit OR, which ruins relevance.
        self.assertIn('TITLE_ABS:"supplementation"', clauses[0])
        self.assertIn(' AND ', clauses[0])
        self.assertLess(clauses[1].count(' AND '), clauses[0].count(' AND '))

    def test_empty_query_returns_nothing(self):
        self.assertEqual(ss.search_literature(''), [])
        self.assertEqual(ss.search_literature('   '), [])


class RankingTests(SimpleTestCase):
    def _search(self, records, query='caffeine endurance performance', limit=3):
        with patch.object(ss, '_get', return_value=records) as get:
            results = ss.search_literature(query, limit=limit)
        return results, get

    def test_on_topic_beats_more_cited_but_off_topic(self):
        """The failure that motivated title scoring: a hugely cited review that
        merely mentions the terms outranked the paper actually about them."""
        results, _ = self._search([
            _record('Interventions for preventing falls in older people',
                    year=2012, citations=1439),
            _record('Effects of caffeine on endurance performance: a meta-analysis',
                    year=2022, citations=37),
        ])
        self.assertIn('caffeine', results[0]['title'].lower())

    def test_citations_break_ties_between_equally_relevant_papers(self):
        results, _ = self._search([
            _record('Caffeine and endurance performance in cyclists',
                    year=2020, citations=5),
            _record('Caffeine and endurance performance in runners',
                    year=2020, citations=500),
        ])
        self.assertEqual(results[0]['citations'], 500)

    def test_citation_rate_is_age_adjusted(self):
        """A 2-year-old paper with 100 citations is a stronger signal than a
        20-year-old one with 150."""
        results, _ = self._search([
            _record('Caffeine endurance performance old', year=2006, citations=150),
            _record('Caffeine endurance performance recent', year=2024, citations=100),
        ])
        self.assertTrue(results[0]['title'].endswith('recent'))

    def test_results_are_capped_at_limit(self):
        results, _ = self._search(
            [_record(f'Caffeine endurance performance study {i}') for i in range(20)],
            limit=3,
        )
        self.assertEqual(len(results), 3)

    def test_duplicates_across_tiers_are_collapsed(self):
        dupe = _record('Caffeine endurance performance', doi='10.1/x')
        results, _ = self._search([dupe, dict(dupe)])
        self.assertEqual(len(results), 1)


class SerializationTests(SimpleTestCase):
    def test_author_string_becomes_a_citation_name(self):
        self.assertEqual(
            ss._authors({'authorString': 'Schoenfeld BJ, Aragon AA, Krieger JW'}),
            'Schoenfeld et al.')
        self.assertEqual(ss._authors({'authorString': 'Grgic J'}), 'Grgic')
        self.assertEqual(ss._authors({'authorString': ''}), '')

    def test_url_prefers_doi_then_pubmed(self):
        self.assertEqual(ss._url({'doi': '10.1136/bjsports-2017-097608'}),
                         'https://doi.org/10.1136/bjsports-2017-097608')
        self.assertEqual(ss._url({'pmid': '28698222'}),
                         'https://pubmed.ncbi.nlm.nih.gov/28698222/')
        self.assertEqual(ss._url({'id': '123', 'source': 'MED'}),
                         'https://europepmc.org/article/MED/123')

    def test_result_carries_everything_needed_to_cite_it(self):
        with patch.object(ss, '_get', return_value=[_record('Caffeine study')]):
            result = ss.search_literature('caffeine', limit=1)[0]
        for field in ('title', 'authors', 'year', 'journal', 'doi', 'url',
                      'citations', 'study_type'):
            self.assertIn(field, result)


class FailureModeTests(SimpleTestCase):
    def test_network_failure_yields_no_results_rather_than_raising(self):
        import requests
        with patch.object(ss.requests, 'get',
                          side_effect=requests.RequestException('boom')):
            self.assertEqual(ss.search_literature('caffeine performance'), [])

    def test_call_budget_is_respected_when_nothing_matches(self):
        with patch.object(ss, '_get', return_value=[]) as get:
            self.assertEqual(ss.search_literature('a very long unmatchable query here'), [])
        self.assertLessEqual(get.call_count, ss._MAX_CALLS)


class ToolWrapperTests(SimpleTestCase):
    def test_empty_result_tells_the_model_not_to_answer_from_memory(self):
        import json
        from chiron.tools import scientific_search
        with patch.object(ss, 'search_literature', return_value=[]):
            payload = json.loads(scientific_search.invoke({'query': 'xyzzy'}))
        self.assertEqual(payload['results'], [])
        self.assertIn('memoria', payload['note'])

    def test_results_are_returned_under_the_results_key(self):
        """`agent._extract_sources` reads `results`; renaming it would silently
        drop every citation from the UI."""
        import json
        from chiron.tools import scientific_search
        with patch.object(ss, 'search_literature',
                          return_value=[{'title': 'T', 'url': 'u'}]):
            payload = json.loads(scientific_search.invoke({'query': 'protein'}))
        self.assertEqual(payload['results'][0]['title'], 'T')
