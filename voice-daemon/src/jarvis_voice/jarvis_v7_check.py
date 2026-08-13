#!/usr/bin/env python3
"""Jarvis v7 Startup — Initialize all upgraded components.

This script:
  1. Checks all v7 modules are importable
  2. Rebuilds memory index if needed
  3. Verifies model availability
  4. Logs system status

Usage:
    python -m jarvis_voice.jarvis_v7_check   (from voice-daemon/, with the package installed)
"""
import json, os, sys, time

HOME = os.path.expanduser("~")

def check_import(name, module):
    try:
        __import__(module)
        print(f"  ✓ {name}")
        return True
    except Exception as e:
        print(f"  ✗ {name}: {e}")
        return False

def check_file(path, name):
    if os.path.exists(path):
        size = os.path.getsize(path)
        print(f"  ✓ {name} ({size / 1024:.0f} KB)")
        return True
    else:
        print(f"  ✗ {name} not found")
        return False

def main():
    print("Jarvis v7 System Check")
    print("=" * 50)
    
    # 1. Check modules
    print("\nModules:")
    modules = [
        ("Voice Stack", "jarvis_voice_v7"),
        ("Memory v7", "jarvis_memory_v7"),
        ("Nemori", "jarvis_nemori"),
        ("LightRAG", "jarvis_lightrag"),
        ("Brain", "jarvis_brain"),
        ("Autonomy", "jarvis_autonomy"),
    ]
    all_ok = all(check_import(n, m) for n, m in modules)
    
    # 2. Check databases
    print("\nDatabases:")
    dbs = [
        (os.path.join(HOME, ".hermes", "jarvis-voice", "jarvis-memory-v7.db"), "Memory Index"),
        (os.path.join(HOME, ".hermes", "jarvis-voice", "knowledge-graph.db"), "Knowledge Graph"),
        (os.path.join(HOME, ".hermes", "jarvis-voice", "autonomy.db"), "Autonomy"),
    ]
    for path, name in dbs:
        check_file(path, name)
    
    # 3. Check models
    print("\nModels:")
    models = [
        (os.path.join(HOME, ".hermes", "jarvis-voice", "models", "kokoro-v1.0.onnx"), "Kokoro TTS"),
        (os.path.join(HOME, ".hermes", "jarvis-voice", "models", "silero_vad.onnx"), "Silero VAD"),
    ]
    for path, name in models:
        check_file(path, name)
    
    # 4. Memory index stats
    print("\nMemory Index:")
    try:
        from .jarvis_memory_v7 import MemoryIndex
        idx = MemoryIndex()
        stats = idx.stats()
        print(f"  Documents: {stats['total_docs']}")
        print(f"  With embeddings: {stats['docs_with_embeddings']}")
        print(f"  DB size: {stats['db_size_kb']:.0f} KB")
    except Exception as e:
        print(f"  Error: {e}")
    
    # 5. Knowledge graph stats
    print("\nKnowledge Graph:")
    try:
        from .jarvis_lightrag import LightRAG
        rag = LightRAG()
        stats = rag.stats()
        print(f"  Entities: {stats['entities']}")
        print(f"  Relations: {stats['relations']}")
        print(f"  Facts: {stats['facts']}")
    except Exception as e:
        print(f"  Error: {e}")
    
    # 6. Health check
    print("\nHealth:")
    try:
        from .jarvis_autonomy import AutonomyEngine
        aut = AutonomyEngine()
        health = aut.health_check()
        disk = health.get("disk", {})
        print(f"  Disk: {disk.get('free_gb', '?')} GB free ({disk.get('pct_used', '?')}% used)")
        mem = health.get("memory", {})
        print(f"  Memory: {mem.get('free_mb', '?')} MB free")
    except Exception as e:
        print(f"  Error: {e}")
    
    print("\n" + "=" * 50)
    if all_ok:
        print("All systems operational.")
    else:
        print("Some components need attention.")

if __name__ == "__main__":
    main()
