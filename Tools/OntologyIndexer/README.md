# Task workspace Ontology

当前覆盖 Mac/iPhone 的任务文档编辑、保存/草稿/撤销，以及 Mac 页面接线、退出保存、系统面板隔离、附件持久化、助手提交、回想与财务统计的部分入口和测试引用。开发图谱不包含个人任务内容；查询与校验仅读取仓库，生成文件写入被忽略的 `.build/ontology/`。

## 使用

需要 Xcode 的 `xcrun swiftc`、Python 3.9+、`jsonschema`。本机已有依赖；新开发环境可在自己的虚拟环境安装 `requirements.txt`。

```sh
python3 Tools/OntologyIndexer/ontology.py build
python3 Tools/OntologyIndexer/ontology.py check
python3 Tools/OntologyIndexer/ontology.py query '标题修改'
python3 Tools/OntologyIndexer/ontology.py query 'code.store.save'
python3 -m unittest discover -s Tools/OntologyIndexer -p 'test_*.py'
```

`ontology/task-workspace.json` 是人工审核的业务、符号绑定及关系；JSON Schema 限制类型。`build` 通过 Swift 编译器的 `-dump-parse` 提取限定符号与当前源码范围，拒绝缺失/重复绑定，并为源码、契约、证据和工具保存 SHA-256。`check/query` 若发现内容变化会拒绝返回旧行号，要求重建。

这是语法声明索引，尚未接入 IndexStoreDB、完整跨平台编译索引或运行 trace。`invokes` 边来自源码核对，可能经过界面回调接线；不能当作编译器已解析的全量调用图。`verified_by` 只表示关联测试，不表示本次测试已经运行通过。实际运行结果见 QA 文档。

查询返回受限局部子图和精确文件范围。未纳管的功能返回空结果；诊断阶段不给没有证据的根因结论或概率。后续按已批准设计增加声明签名的语义解析、运行事件与故障案例；不要求 App 用户安装本工具。

## 维护

代码或规则变更时更新绑定和证据，运行 `build`、`check` 及工具测试。CI 可运行相同命令；当前仓库尚未新增 CI workflow。不要手改生成索引中的行号，不要将个人数据复制进本目录。
