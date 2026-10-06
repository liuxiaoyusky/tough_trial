import test from 'node:test';
import assert from 'node:assert/strict';
import {validateBundle, mergeAnnotations, onImage} from './web/annotations.mjs';
const note={id:'n1',page:'today',feature:'ui.today',revision:'a'.repeat(64),title:'今天',provenance:'模拟器',x:.2,y:.4,strokes:[[{x:.2,y:.4},{x:.5,y:.6}]],text:'移动按钮',resolved:false,updatedAt:'2026-09-30T12:00:00Z'};
const bundle=annotations=>({schema:1,project:'tough-trial',annotations});
test('annotation roundtrip preserves drawing and image revision',()=>assert.deepEqual(validateBundle(JSON.parse(JSON.stringify(bundle([note]))),'tough-trial'),[note]));
test('old image annotations never appear on a replacement image',()=>assert.equal(onImage([note],{id:'today',revision:'b'.repeat(64)}).length,0));
test('import retains newest existing edit and preserves unrelated notes',()=>assert.deepEqual(mergeAnnotations([note,{...note,id:'n2'}],[{...note,text:'old',updatedAt:'2026-09-29T00:00:00Z'}]),[note,{...note,id:'n2'}]));
test('same ID cannot silently move to another image',()=>assert.throws(()=>mergeAnnotations([note],[{...note,revision:'b'.repeat(64)}])));
test('wrong project, duplicate IDs and invalid stroke coordinates are rejected',()=>{
 assert.throws(()=>validateBundle(bundle([note]),'another'));
 assert.throws(()=>validateBundle(bundle([note,note]),'tough-trial'));
 assert.throws(()=>validateBundle(bundle([{...note,strokes:[[{x:NaN,y:.5}]]}]),'tough-trial'));
});
