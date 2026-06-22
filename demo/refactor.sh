#!/bin/bash
# Comprehensive refactor script for Demo project
# Reflects the Laravel-style directory structure after refactoring
set -e
cd /Users/tuoke/Desktop/worktree/photon/demo

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

# app/models/ files
for f in app/models/*.v; do
    sed -i 's/^module main$/module models/' "$f"
done

# app/repositories/ files
for f in app/repositories/*.v; do
    sed -i 's/^module main$/module repositories/' "$f"
done

# app/services/ files
for f in app/services/*.v; do
    sed -i 's/^module main$/module services/' "$f"
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

# Step 2: Directory structure overview (Laravel-style skeleton)
echo ""
echo "=== Final Directory Structure ==="
echo ""
echo "demo/"
echo "├── app/"
echo "│   ├── http/"
echo "│   │   ├── Kernel.v"
echo "│   │   ├── middleware/"
echo "│   │   │   └── registry.v"
echo "│   │   └── resources/"
echo "│   │       ├── category_tag_resource.v"
echo "│   │       ├── collection.v"
echo "│   │       ├── comment_resource.v"
echo "│   │       ├── post_resource.v"
echo "│   │       └── user_resource.v"
echo "│   ├── models/"
echo "│   │   └── models.v"
echo "│   ├── repositories/"
echo "│   │   └── repositories.v"
echo "│   └── services/"
echo "│       ├── emails.v"
echo "│       ├── events.v"
echo "│       ├── jobs.v"
echo "│       ├── scheduler.v"
echo "│       └── services.v"
echo "├── bootstrap/"
echo "│   ├── app.v"
echo "│   └── console.v"
echo "├── config/"
echo "│   ├── app.v"
echo "│   ├── app_config.v"
echo "│   ├── auth.v"
echo "│   ├── cache.v"
echo "│   ├── database.v"
echo "│   ├── env_helpers.v"
echo "│   ├── jwt.v"
echo "│   ├── logging.v"
echo "│   ├── mail.v"
echo "│   ├── storage.v"
echo "│   └── web.v"
echo "├── database/"
echo "│   ├── database.v"
echo "│   ├── factories/"
echo "│   ├── migrations/"
echo "│   ├── seeders/"
echo "│   └── transactional.v"
echo "├── providers/"
echo "│   ├── app_service_provider.v"
echo "│   ├── auth_service_provider.v"
echo "│   ├── boot_context.v"
echo "│   ├── cache_service_provider.v"
echo "│   ├── database_service_provider.v"
echo "│   ├── event_service_provider.v"
echo "│   ├── queue_service_provider.v"
echo "│   ├── repository_service_provider.v"
echo "│   ├── service_service_provider.v"
echo "│   └── web_service_provider.v"
echo "├── routes/"
echo "│   ├── api.v"
echo "│   └── web.v"
echo "├── tests/"
echo "│   ├── eager_loading_test.v"
echo "│   ├── exception_test.v"
echo "│   ├── factory_test.v"
echo "│   ├── refresh_database.v"
echo "│   ├── soft_delete_test.v"
echo "│   ├── test_case.v"
echo "│   └── validation_test.v"
echo "├── util/"
echo "│   └── util.v"
echo "├── app_struct.v              ← App/Context struct definitions"
echo "├── command_docs.v            ← CLI commands (split)"
echo "├── command_migrate.v"
echo "├── command_queue.v"
echo "├── command_register.v"
echo "├── command_routes.v"
echo "├── command_scheduler.v"
echo "├── command_seed.v"
echo "├── command_serve.v"
echo "├── command_stats.v"
echo "├── controller_auth.v         ← Controllers (split)"
echo "├── controller_category.v"
echo "├── controller_comment.v"
echo "├── controller_dto.v"
echo "├── controller_post.v"
echo "├── controller_system.v"
echo "├── controller_tag.v"
echo "├── controller_upload.v"
echo "├── controller_user.v"
echo "├── context_response.v        ← Context response helpers"
echo "├── main.v                    ← Entry point"
echo "├── Makefile"
echo "├── refactor.sh"
echo "└── v.mod"
echo ""
echo "=== Refactoring complete ==="
