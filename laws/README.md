# 法律知识库数据

本目录存放需要入库到 LanceDB 的法律文档（Markdown 格式）。

## 数据来源

| 文件名 | 内容 | 来源 |
|--------|------|------|
| `civil-code.md` | 《中华人民共和国民法典》核心条文 | 全国人大官网 |
| `civil-procedure-law.md` | 《民事诉讼法》（2024修正版） | 全国人大官网 |
| `judicial-interpretation-lending.md` | 民间借贷司法解释 | 最高法官网 |
| `guiding-case-XXX.md` | 指导案例 | 中国裁判文书网 |

## 文件格式要求

每个 `.md` 文件按条文分块，使用 `##` 标题标记每一条：

```markdown
## 第一百八十八条
向人民法院请求保护民事权利的诉讼时效期间为三年。法律另有规定的，依照其规定。

## 第一百八十九条
当事人约定同一债务分期履行的……
```

## 入库命令

```bash
python3 scripts/ingest-law.py --input ./laws/ --db ~/.openclaw/memory/lancedb --table chinese-law
```

## 注意事项

- Embedding 模型推荐 `BAAI/bge-small-zh-v1.5`（512维，中文优化，国内可下载）
- 入库时的向量维度必须与 OpenClaw memory-lancedb 查询时的维度一致
- 首次入库需要下载模型，约 100MB
