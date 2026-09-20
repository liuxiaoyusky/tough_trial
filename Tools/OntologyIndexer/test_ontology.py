import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import ontology


class OntologyTests(unittest.TestCase):
    def setUp(self):
        self.graph = json.loads((ontology.ROOT / ontology.GRAPH).read_text())
        self.schema = json.loads((ontology.ROOT / ontology.SCHEMA).read_text())

    def test_source_ranges_keep_nested_scopes_despite_literal_newlines(self):
        parsed = ontology.declarations('''(source_file "x.swift"
  (class_decl range=[x.swift:1:1 - line:20:1] "Outer"
    (func_decl range=[x.swift:2:1 - line:8:1] "first(a:)"
      (string_literal_expr value="a
literal on unindented line")
    (struct_decl range=[x.swift:9:1 - line:15:1] "Inner"
      (func_decl range=[x.swift:10:1 - line:12:1] "run()")
    (func_decl range=[x.swift:16:1 - line:19:1] "first(b:)")
  (extension_decl range=[x.swift:21:1 - line:23:1] "Other"
    (func_decl range=[x.swift:22:1 - line:22:30] "run()")))''')
        symbols = [s['symbol'] for s in parsed]
        self.assertIn('Outer.Inner.run()', symbols)
        self.assertIn('Outer.first(b:)', symbols)
        self.assertIn('Other.run()', symbols)
        self.assertEqual(next(s for s in parsed if s['symbol'] == 'Outer.first(b:)')['range'], [16, 1, 19, 1])

    def test_unknown_node_in_edge_is_rejected(self):
        self.graph['edges'][0]['to'] = 'does.not.exist'
        with self.assertRaisesRegex(ValueError, '不存在'):
            ontology.validate(self.graph, self.schema, ontology.ROOT)

    def test_duplicate_ids_and_wrong_verification_type_are_rejected(self):
        duplicate = copy.deepcopy(self.graph)
        duplicate['nodes'].append(duplicate['nodes'][0])
        with self.assertRaisesRegex(ValueError, '重复'):
            ontology.validate(duplicate, self.schema, ontology.ROOT)
        self.graph['edges'][0].update(relation='verified_by', to='core.tasks')
        with self.assertRaisesRegex(ValueError, '测试用例'):
            ontology.validate(self.graph, self.schema, ontology.ROOT)

    def test_stale_index_never_returns_old_ranges(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'source.swift').write_text('old')
            index = {'formatVersion': 1, 'files': {'source.swift': ontology.digest(b'old')}}
            (root / 'index.json').write_text(json.dumps(index))
            ontology.load_current(root, Path('index.json'))
            (root / 'source.swift').write_text('new')
            with self.assertRaisesRegex(ValueError, '过期'):
                ontology.load_current(root, Path('index.json'))

    def test_path_traversal_cannot_read_outside_repository(self):
        with self.assertRaisesRegex(ValueError, '越出仓库'):
            ontology.safe_path(ontology.ROOT, '../outside.swift')

    def test_query_is_bounded_and_no_match_has_no_guessed_result(self):
        index = {'graph': self.graph, 'sourceFingerprint': 'fixture', 'coverage': 'test'}
        result = ontology.query(index, '标题修改', limit=8)
        self.assertLessEqual(len(result['nodes']), 8)
        self.assertIn('capability.tasks.edit_document', result['matches'])
        self.assertEqual(ontology.query(index, 'unmapped feature')['nodes'], [])

    def test_missing_symbol_cannot_build_a_successful_index(self):
        # An actual compiler parse on the current graph first proves all maintained selectors resolve.
        index = ontology.build()
        self.assertTrue(any('location' in n for n in index['graph']['nodes']))
        with patch.object(ontology, 'declarations', return_value=[]):
            with self.assertRaisesRegex(ValueError, '须唯一解析'):
                ontology.build()


if __name__ == '__main__':
    unittest.main()
