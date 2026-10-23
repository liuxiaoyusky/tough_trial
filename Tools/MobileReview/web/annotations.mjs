export const keyFor = project => `native-review:${project}:v1`;
export function validateBundle(bundle, project) {
  if (!bundle || bundle.schema !== 1 || bundle.project !== project || !Array.isArray(bundle.annotations) || bundle.annotations.length > 1000) throw Error('不是此项目的有效批注文件');
  const ids = new Set();
  for (const n of bundle.annotations) {
    if (!n || typeof n.id !== 'string' || !n.id || n.id.length > 100 || ids.has(n.id)) throw Error('批注编号无效或重复');
    ids.add(n.id);
    if (typeof n.page !== 'string' || !n.page || typeof n.feature !== 'string' || typeof n.revision !== 'string' || !/^[a-f0-9]{64}$/.test(n.revision)) throw Error('缺少画面版本');
    if (typeof n.text !== 'string' || !n.text.trim() || n.text.length > 4000 || typeof n.resolved !== 'boolean') throw Error('批注内容无效');
    if (typeof n.title !== 'string' || typeof n.provenance !== 'string' || typeof n.updatedAt !== 'string' || !Number.isFinite(Date.parse(n.updatedAt))) throw Error('批注来源无效');
    if (!point(n) || !Array.isArray(n.strokes) || n.strokes.length > 20 || !n.strokes.every(s => Array.isArray(s) && s.length > 0 && s.length <= 4000 && s.every(point))) throw Error('圈画坐标无效');
  }
  return bundle.annotations;
}
function point(p) { return p && [p.x,p.y].every(v => typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= 1); }
export function mergeAnnotations(existing, incoming) {
  const result = new Map(existing.map(n => [n.id,n]));
  for (const n of incoming) {
    const old = result.get(n.id);
    if (old && (old.page !== n.page || old.revision !== n.revision)) throw Error('同一批注编号对应不同画面；未导入');
    if (!old || Date.parse(n.updatedAt) > Date.parse(old.updatedAt)) result.set(n.id,n);
  }
  return [...result.values()];
}
export function onImage(notes, page) { return notes.filter(n => n.page === page.id && n.revision === page.revision); }
