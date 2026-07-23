#!/usr/bin/env python3
"""
CLI for querying a GraphRAG index with an LLM.

Usage:
  python shell/adhoc_query.py "Which modules are riskiest to refactor?"
  python shell/adhoc_query.py "What security vulnerabilities exist?" --root-dir graph_rag_app/source
  python shell/adhoc_query.py "List dependencies" --local --retry-count 5
"""
import argparse
import asyncio
import os
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from utils.graphrag_utils import DependencyAnalyzer
from loaders.default_asset_loader import DefaultAssetLoader

parser = argparse.ArgumentParser(description="Query a GraphRAG index with an LLM")
parser.add_argument("question", help="Question to ask")
parser.add_argument("--root-dir", default=".", help="GraphRAG root directory containing output/ parquet files")
parser.add_argument("--local", action="store_true", help="Use local search instead of global search")
parser.add_argument("--retry-count", type=int, default=3, help="Number of retries on failure")
args = parser.parse_args()

analyzer = DependencyAnalyzer(root_dir=args.root_dir)
result = asyncio.run(analyzer.query_with_llm(
    args.question,
    retry_count=args.retry_count,
    use_global=not args.local,
))

timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
result_file = f"adhoc_query_{timestamp}.txt"

Path(result_file).write_text(f"Question: {args.question}\n\nAnswer:\n{result}")

DefaultAssetLoader().log_results(result_file, artifact_path="results/adhoc_queries")

print(result)
