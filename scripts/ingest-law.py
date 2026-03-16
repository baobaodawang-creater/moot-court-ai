#!/usr/bin/env python3
"""
Moot Court AI - 法律知识库入库脚本
将法律文档（Markdown）导入 LanceDB 向量数据库供法官 Agent RAG 检索。

用法:
    python3 scripts/ingest-law.py --input ./laws/ --db ~/.openclaw/memory/lancedb --table chinese-law

输入文件格式 (Markdown):
    每个 .md 文件应包含法律条文，建议按「条」为单位用 ## 标题分隔：

    ## 第一百八十八条
    向人民法院请求保护民事权利的诉讼时效期间为三年。法律另有规定的，依照其规定。

    ## 第一百八十九条
    当事人约定同一债务分期履行的……

元数据通过文件名约定:
    - civil-code.md          -> law_name="民法典"
    - civil-procedure-law.md -> law_name="民事诉讼法"
    - guiding-case-001.md    -> category="guiding_case"
"""

import argparse
import os
import re
import json
from pathlib import Path
from datetime import datetime

def parse_law_file(filepath: str) -> list[dict]:
    """将一个法律 Markdown 文件拆分为条文级别的 chunks。"""
    
    filename = Path(filepath).stem
    
    # 根据文件名推断元数据
    law_name_map = {
        "civil-code": "中华人民共和国民法典",
        "civil-procedure-law": "中华人民共和国民事诉讼法",
        "judicial-interpretation": "司法解释",
    }
    
    law_name = law_name_map.get(filename, filename)
    category = "guiding_case" if "guiding-case" in filename else "statute"
    
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    # 按 ## 标题分块
    sections = re.split(r'\n(?=## )', content)
    
    chunks = []
    for section in sections:
        section = section.strip()
        if not section:
            continue
        
        # 提取标题（条文编号）
        lines = section.split('\n')
        title = lines[0].lstrip('#').strip()
        body = '\n'.join(lines[1:]).strip()
        
        if not body:
            continue
        
        # 提取条文编号
        article_match = re.search(r'第[一二三四五六七八九十百千\d]+条', title)
        article_number = article_match.group(0) if article_match else ""
        
        chunks.append({
            "text": f"{title}\n{body}",
            "law_name": law_name,
            "article_number": article_number,
            "category": category,
            "source_file": filepath,
            "chunk_title": title,
        })
    
    return chunks


def ingest_to_lancedb(chunks: list[dict], db_path: str, table_name: str, model_name: str):
    """将 chunks 向量化并写入 LanceDB。"""
    
    try:
        import lancedb
        from sentence_transformers import SentenceTransformer
    except ImportError:
        print("❌ 缺少依赖。请运行: pip install lancedb sentence-transformers")
        print("   如果使用系统 Python: pip install --break-system-packages lancedb sentence-transformers")
        return
    
    print(f"   加载 Embedding 模型: {model_name}")
    print("   （首次运行需要下载模型，可能需要几分钟）")
    model = SentenceTransformer(model_name)
    
    # 获取向量维度
    test_vec = model.encode(["test"])
    dim = test_vec.shape[1]
    print(f"   ✅ 模型已加载，向量维度: {dim}")
    
    # ⚠️ 重要：确认此维度与 OpenClaw memory-lancedb 插件的默认维度一致
    # 如果不一致，法官检索时会报错:
    # "No vector column found to match with the query vector dimension: XXX"
    # 解决方案：在 openclaw.json 中配置 memory-lancedb 使用相同的 embedding 模型
    
    print(f"   生成 Embeddings ({len(chunks)} 条)...")
    texts = [c["text"] for c in chunks]
    vectors = model.encode(texts, show_progress_bar=True)
    
    # 构建 LanceDB 记录
    records = []
    for i, chunk in enumerate(chunks):
        records.append({
            "vector": vectors[i].tolist(),
            "text": chunk["text"],
            "law_name": chunk["law_name"],
            "article_number": chunk["article_number"],
            "category": chunk["category"],
            "chunk_title": chunk["chunk_title"],
            "source_file": chunk["source_file"],
            "ingested_at": datetime.now().isoformat(),
        })
    
    print(f"   写入 LanceDB: {db_path}/{table_name}")
    db = lancedb.connect(db_path)
    
    # 如果表已存在，先删除
    existing_tables = db.table_names()
    if table_name in existing_tables:
        db.drop_table(table_name)
        print(f"   ⚠️  已删除旧表 {table_name}")
    
    table = db.create_table(table_name, records)
    print(f"   ✅ 已写入 {len(records)} 条记录到表 {table_name}")
    print(f"   向量维度: {dim}")
    
    # 验证检索
    print("\n   验证检索...")
    query_vec = model.encode(["合同解除"]).tolist()[0]
    results = table.search(query_vec).limit(3).to_list()
    print(f"   检索 '合同解除' 返回 {len(results)} 条结果:")
    for r in results:
        print(f"     - [{r.get('law_name', '')}] {r.get('chunk_title', '')[:50]}")


def main():
    parser = argparse.ArgumentParser(description="法律知识库入库脚本")
    parser.add_argument("--input", required=True, help="法律文档目录路径")
    parser.add_argument("--db", default=os.path.expanduser("~/.openclaw/memory/lancedb"),
                        help="LanceDB 数据库路径")
    parser.add_argument("--table", default="chinese-law", help="表名")
    parser.add_argument("--model", default="BAAI/bge-small-zh-v1.5",
                        help="Embedding 模型 (默认: BAAI/bge-small-zh-v1.5, 512维, 中文优化)")
    args = parser.parse_args()
    
    # 推荐的中文 Embedding 模型（全部支持国内下载）:
    # - BAAI/bge-small-zh-v1.5  (512维, 速度快, 推荐)
    # - BAAI/bge-base-zh-v1.5   (768维, 更准确)
    # - BAAI/bge-large-zh-v1.5  (1024维, 最准确但最慢)
    # - shibing624/text2vec-base-chinese (768维, 备选)
    
    print("============================================")
    print("  🏛️  法律知识库入库")
    print("============================================")
    print(f"  输入目录: {args.input}")
    print(f"  数据库:   {args.db}")
    print(f"  表名:     {args.table}")
    print(f"  模型:     {args.model}")
    print("")
    
    # 扫描输入文件
    input_dir = Path(args.input)
    if not input_dir.exists():
        print(f"❌ 输入目录不存在: {args.input}")
        return
    
    md_files = list(input_dir.glob("**/*.md"))
    if not md_files:
        print(f"❌ 未找到 .md 文件: {args.input}")
        return
    
    print(f"[1/3] 解析法律文档 ({len(md_files)} 个文件)...")
    all_chunks = []
    for f in md_files:
        chunks = parse_law_file(str(f))
        all_chunks.extend(chunks)
        print(f"   {f.name}: {len(chunks)} 条")
    
    print(f"   共计 {len(all_chunks)} 条法律条文/案例")
    
    if not all_chunks:
        print("❌ 没有有效的法律条文。请检查文件格式。")
        return
    
    print(f"\n[2/3] 向量化与入库...")
    os.makedirs(args.db, exist_ok=True)
    ingest_to_lancedb(all_chunks, args.db, args.table, args.model)
    
    print(f"\n[3/3] 完成!")
    print("")
    print("============================================")
    print("  ✅ 法律知识库构建完成")
    print("============================================")
    print(f"  记录数: {len(all_chunks)}")
    print(f"  数据库: {args.db}/{args.table}")
    print("")


if __name__ == "__main__":
    main()
