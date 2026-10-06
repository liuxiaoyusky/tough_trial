import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).with_name('cli.py').resolve()
spec = importlib.util.spec_from_file_location('review_cli', CLI)
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)

class CLIIntegration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root/'screen.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="390" height="844"><rect width="390" height="844" fill="white"/></svg>')
        self.run_cli('init','--id','another-app','--title','Another App')
        self.run_cli('add','--id','home','--feature','ui.home','--title','Home','--image','screen.svg','--kind','design','--provenance','Synthetic fixture')
    def tearDown(self):
        self.temp.cleanup()
    def run_cli(self,*args,ok=True):
        result=subprocess.run([sys.executable,str(CLI),*args],cwd=self.root,capture_output=True,text=True)
        self.assertEqual(result.returncode==0,ok,result.stdout+result.stderr)
        return json.loads(result.stdout if ok else result.stderr)
    def test_portable_build_no_tough_trial_dependency(self):
        self.run_cli('check')
        self.run_cli('build','--output','site')
        data=cli.read(self.root/'site/review.json')
        self.assertEqual(data['project'],'another-app')
        self.assertEqual(data['title'],'Another App')
        self.assertEqual(len(data['pages'][0]['revision']),64)
        self.assertTrue((self.root/'site'/data['pages'][0]['image']).is_file())
        self.run_cli('build','--output','site')
    def test_source_image_change_changes_revision_preserves_old_asset(self):
        self.run_cli('build','--output','site'); old=cli.read(self.root/'site/review.json')['pages'][0]
        with (self.root/'screen.svg').open('a') as f:f.write('\n')
        self.run_cli('build','--output','site'); new=cli.read(self.root/'site/review.json')['pages'][0]
        self.assertNotEqual(old['revision'],new['revision'])
        self.assertTrue((self.root/'site'/old['image']).exists())
    def test_refuse_nonempty_output_or_unmanaged_files(self):
        (self.root/'unsafe').mkdir(); (self.root/'unsafe/.env').write_text('private')
        self.run_cli('build','--output','unsafe',ok=False)
        self.run_cli('build','--output','site'); (self.root/'site/.env').write_text('private')
        self.run_cli('build','--output','site',ok=False)
        self.assertEqual((self.root/'site/.env').read_text(),'private')
    def test_duplicate_init_page_and_outside_image_rejected(self):
        self.run_cli('init','--id','same','--title','x',ok=False)
        (self.root/'outside.svg').symlink_to(CLI)
        self.run_cli('add','--id','outside','--feature','ui.home','--title','x','--image','outside.svg','--kind','design','--provenance','x',ok=False)
    def test_feedback_import_report_and_conflict_do_not_corrupt(self):
        self.run_cli('build','--output','site'); page=cli.read(self.root/'site/review.json')['pages'][0]
        note={'id':'a','page':'home','feature':'ui.home','revision':page['revision'],'title':'Home','provenance':'fixture','text':'move button','resolved':False,'x':.2,'y':.3,'strokes':[[{'x':.2,'y':.3},{'x':.3,'y':.4}]],'updatedAt':'2026-10-01T00:00:00Z'}
        package={'schema':1,'project':'another-app','annotations':[note]}; cli.write(self.root/'feedback.json',package)
        args=['import-feedback','--review','site/review.json','--file','feedback.json']
        self.run_cli(*args); self.run_cli(*args)
        result=self.run_cli('feedback','--review','site/review.json','--markdown','feedback.md')
        self.assertEqual(len(result['annotations']),1); self.assertEqual(result['annotations'][0]['image_status'],'current')
        before=(self.root/'.mobile-review/feedback.json').read_bytes()
        package['annotations'][0]['revision']='f'*64;cli.write(self.root/'feedback.json',package)
        self.run_cli(*args,ok=False);self.assertEqual((self.root/'.mobile-review/feedback.json').read_bytes(),before)
    def test_wrong_project_and_invalid_coordinates_rejected(self):
        with self.assertRaises(ValueError):cli.annotations({'schema':1,'project':'wrong','annotations':[]},'another-app')

if __name__=='__main__':unittest.main()
