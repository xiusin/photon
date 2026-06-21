#!/bin/bash
# Comprehensive refactor script for Demo project
set -e
cd /workspace/Demo

# Step 1: Change module declarations in all sub-directory .v files
echo "=== Step 1: Changing module declarations ==="

# config/ files - already changed to module config

# bootstrap/ files
for f in bootstrap/app.v bootstrap/console.v; do
    sed -i 's/^module main$/module bootstrap/' "$f"
done

# providers/ files
for f in providers/*.v; do
    sed -i 's/^module main$/module providers/' "$f"
done

# routes/ files
for f in routes/*.v; do
    sed -i 's/^module main$/module routes/' "$f"
done

# tests/ files
for f in tests/*.v; do
    sed -i 's/^module main$/module tests/' "$f"
done

# app/http/ files
for f in app/http/*.v; do
    sed -i 's/^module main$/module http/' "$f"
done

# app/http/middleware/ files
for f in app/http/middleware/*.v; do
    sed -i 's/^module main$/module middleware/' "$f"
done

# app/http/resources/ files
for f in app/http/resources/*.v; do
    sed -i 's/^module main$/module resources/' "$f"
done

# database/factories/ files
for f in database/factories/*.v; do
    sed -i 's/^module main$/module factories/' "$f"
done

# database/migrations/ files
for f in database/migrations/*.v; do
    sed -i 's/^module main$/module migrations/' "$f"
done

# database/seeders/ files
for f in database/seeders/*.v; do
    sed -i 's/^module main$/module seeders/' "$f"
done

echo "=== Step 1 complete ==="
