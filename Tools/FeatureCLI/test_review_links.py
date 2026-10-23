import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from review_links import inspect


class ReviewLinksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['docs', 'ontology', 'outputs/contacts-design-review/assets']:
            (self.root / folder).mkdir(parents=True)
        (self.root / 'ontology/task-workspace.json').write_text('{"nodes":[]}')
        (self.root / 'outputs/contacts-design-review/index.html').write_text("{id:'one',title:'One',description:'View',source:'one.svg'}")
        (self.root / 'outputs/contacts-design-review/assets/one.svg').write_text('<svg/>')
        self.feature = {'id':'ui.one', 'title':'One', 'ontology_refs':[], 'acceptance':[],
                        'evidence':[{'path':'outputs/contacts-design-review/assets/one.svg', 'sha256':hashlib.sha256(b'<svg/>').hexdigest()}],
                        'ui':{'route':'One', 'implementation_status':'design', 'code':[],
                              'review_pages':[{'id':'one', 'image':'outputs/contacts-design-review/assets/one.svg', 'kind':'design'}]}}

    def check(self, features):
        (self.root / 'docs/feature-map.json').write_text(json.dumps({'features':features}))
        return inspect(self.root)

    def test_valid_mapping_and_stale_image_are_distinct(self):
        self.assertTrue(self.check([self.feature])['ok'])
        (self.root / 'outputs/contacts-design-review/assets/one.svg').write_text('<svg>changed</svg>')
        result = self.check([self.feature])
        self.assertEqual(result['pages']['one']['freshness'], 'needs_review')
        self.assertEqual(result['product_verification'], 'not_assessed')

    def test_unmapped_page_fails(self):
        self.feature['ui']['review_pages'] = []
        self.assertFalse(self.check([self.feature])['ok'])

    def test_duplicate_mapping_fails(self):
        other = copy.deepcopy(self.feature)
        other['id'] = 'ui.other'
        self.assertFalse(self.check([self.feature, other])['ok'])

    def test_mismatched_image_fails(self):
        (self.root / 'outputs/contacts-design-review/assets/two.svg').write_text('<svg/>')
        self.feature['ui']['review_pages'][0]['image'] = 'outputs/contacts-design-review/assets/two.svg'
        self.assertFalse(self.check([self.feature])['ok'])

    def test_unknown_ontology_fails(self):
        self.feature['ontology_refs'] = ['invented.id']
        self.assertFalse(self.check([self.feature])['ok'])

    def test_path_escape_fails(self):
        self.feature['ui']['review_pages'][0]['image'] = '../private.svg'
        with self.assertRaises(ValueError):
            self.check([self.feature])


if __name__ == '__main__':
    unittest.main()
