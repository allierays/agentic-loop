#!/usr/bin/env bash
# shellcheck shell=bash
# backup.sh - Database backup management for ralph

# Constants
readonly DEFAULT_MAX_BACKUPS=15
readonly BACKUP_DIR=".backups"
readonly LARGE_DB_THRESHOLD_MB=100

# Quiet mode flag (set via --quiet)
BACKUP_QUIET=false

# Parse MySQL URL into components
# Usage: parse_mysql_url "mysql://user:pass@host:port/dbname"
# Sets: MYSQL_USER, MYSQL_PASSWORD, MYSQL_HOST, MYSQL_PORT, MYSQL_DB
parse_mysql_url() {
  local url="$1"

  # Reset variables
  MYSQL_USER="" MYSQL_PASSWORD="" MYSQL_HOST="" MYSQL_PORT="" MYSQL_DB=""

  # Parse URL: mysql://user:pass@host:port/dbname
  if [[ "$url" =~ mysql://([^:]+):([^@]+)@([^:]+):([0-9]+)/([^?]+) ]]; then
    MYSQL_USER="${BASH_REMATCH[1]}"
    MYSQL_PASSWORD="${BASH_REMATCH[2]}"
    MYSQL_HOST="${BASH_REMATCH[3]}"
    MYSQL_PORT="${BASH_REMATCH[4]}"
    MYSQL_DB="${BASH_REMATCH[5]}"
    return 0
  elif [[ "$url" =~ mysql://([^:]+):([^@]+)@([^/]+)/([^?]+) ]]; then
    MYSQL_USER="${BASH_REMATCH[1]}"
    MYSQL_PASSWORD="${BASH_REMATCH[2]}"
    MYSQL_HOST="${BASH_REMATCH[3]}"
    MYSQL_PORT="3306"
    MYSQL_DB="${BASH_REMATCH[4]}"
    return 0
  fi

  return 1
}

# Cross-platform file size in MB
get_file_size_mb() {
  local file="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f%z "$file" 2>/dev/null | awk '{print int($1/1048576)}'
  else
    stat -c%s "$file" 2>/dev/null | awk '{print int($1/1048576)}'
  fi
}

# Print only if not in quiet mode
backup_info() {
  [[ "$BACKUP_QUIET" == false ]] && print_info "$1"
}

backup_warning() {
  [[ "$BACKUP_QUIET" == false ]] && print_warning "$1"
}

backup_success() {
  [[ "$BACKUP_QUIET" == false ]] && print_success "$1"
}

# ============================================================================
# DATABASE DETECTION
# ============================================================================

# Find SQLite database files (excluding common non-data directories)
detect_sqlite() {
  find . -maxdepth 4 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/.venv/*" \
    -not -path "*/venv/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.backups/*" \
    2>/dev/null
}

# Check for PostgreSQL or Supabase DATABASE_URL
detect_postgres() {
  local url=""

  # Check environment variables (including Supabase variants)
  if [[ -n "${DATABASE_URL:-}" ]]; then
    url="$DATABASE_URL"
  elif [[ -n "${SUPABASE_DB_URL:-}" ]]; then
    url="$SUPABASE_DB_URL"
  elif [[ -n "${POSTGRES_URL:-}" ]]; then
    url="$POSTGRES_URL"
  # Then check .env file
  elif [[ -f ".env" ]]; then
    url=$(grep -E '^(DATABASE_URL|SUPABASE_DB_URL|POSTGRES_URL)=' .env 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
  fi

  # Only return if it's a PostgreSQL URL (includes Supabase which uses postgres://)
  if [[ "$url" =~ ^postgres(ql)?:// ]]; then
    echo "$url"
    return 0
  fi
  return 1
}

# Check for MySQL URL
detect_mysql() {
  local url=""

  # Check MYSQL_URL first
  if [[ -n "${MYSQL_URL:-}" ]]; then
    url="$MYSQL_URL"
  # Then DATABASE_URL if it's mysql
  elif [[ -n "${DATABASE_URL:-}" && "${DATABASE_URL}" =~ ^mysql:// ]]; then
    url="$DATABASE_URL"
  # Then .env file
  elif [[ -f ".env" ]]; then
    url=$(grep -E '^MYSQL_URL=' .env 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    if [[ -z "$url" ]]; then
      url=$(grep -E '^DATABASE_URL=' .env 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
  fi

  if [[ "$url" =~ ^mysql:// ]]; then
    echo "$url"
    return 0
  fi
  return 1
}

# Check for MongoDB URL
detect_mongodb() {
  local url=""

  # Check various env var names
  if [[ -n "${MONGODB_URL:-}" ]]; then
    url="$MONGODB_URL"
  elif [[ -n "${MONGO_URL:-}" ]]; then
    url="$MONGO_URL"
  elif [[ -f ".env" ]]; then
    url=$(grep -E '^MONGO(DB)?_URL=' .env 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
  fi

  if [[ "$url" =~ ^mongodb(\+srv)?:// ]]; then
    echo "$url"
    return 0
  fi
  return 1
}

# ============================================================================
# VERIFICATION FUNCTIONS (post-backup integrity checks)
# ============================================================================

# Verify SQLite backup integrity
verify_sqlite_backup() {
  local backup_file="$1"

  if ! command -v sqlite3 &>/dev/null; then
    return 0  # Can't verify without sqlite3, assume ok
  fi

  local result
  result=$(sqlite3 "$backup_file" "PRAGMA integrity_check;" 2>&1)

  if [[ "$result" == "ok" ]]; then
    return 0
  else
    backup_warning "SQLite integrity check failed: $result"
    return 1
  fi
}

# Verify PostgreSQL backup has valid content
verify_postgres_backup() {
  local backup_file="$1"

  # Check gzip integrity
  if ! gzip -t "$backup_file" 2>/dev/null; then
    backup_warning "PostgreSQL backup gzip corrupted"
    return 1
  fi

  # Check for PostgreSQL dump header
  if ! zcat "$backup_file" 2>/dev/null | head -20 | grep -q "PostgreSQL"; then
    backup_warning "PostgreSQL backup missing valid header"
    return 1
  fi

  return 0
}

# Verify MySQL backup has valid content
verify_mysql_backup() {
  local backup_file="$1"

  # Check gzip integrity
  if ! gzip -t "$backup_file" 2>/dev/null; then
    backup_warning "MySQL backup gzip corrupted"
    return 1
  fi

  # Check for MySQL dump markers
  if ! zcat "$backup_file" 2>/dev/null | head -20 | grep -qE "(MySQL|mysqldump)"; then
    backup_warning "MySQL backup missing valid header"
    return 1
  fi

  return 0
}

# Verify MongoDB backup integrity
verify_mongodb_backup() {
  local backup_file="$1"

  # Check gzip integrity
  if ! gzip -t "$backup_file" 2>/dev/null; then
    backup_warning "MongoDB backup gzip corrupted"
    return 1
  fi

  # Check file has content (mongodump archives have binary content)
  local size
  size=$(get_file_size_mb "$backup_file")
  if [[ "$size" -eq 0 ]]; then
    # Check actual byte size for small DBs
    local bytes
    if [[ "$(uname)" == "Darwin" ]]; then
      bytes=$(stat -f%z "$backup_file" 2>/dev/null)
    else
      bytes=$(stat -c%s "$backup_file" 2>/dev/null)
    fi
    if [[ "$bytes" -lt 100 ]]; then
      backup_warning "MongoDB backup appears empty"
      return 1
    fi
  fi

  return 0
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

# Backup a SQLite database
backup_sqlite() {
  local db_path="$1"
  local backup_dir="$2"
  local timestamp="$3"

  # Extract database name (without extension)
  local db_name
  db_name=$(basename "$db_path" | sed 's/\.[^.]*$//')

  local backup_file="$backup_dir/sqlite/${db_name}-${timestamp}.db"
  mkdir -p "$backup_dir/sqlite"

  # Check file size and warn if large
  local size_mb
  size_mb=$(get_file_size_mb "$db_path")
  if [[ "$size_mb" -gt "$LARGE_DB_THRESHOLD_MB" ]]; then
    backup_warning "Large database (${size_mb}MB): $db_path - backup may be slow"
  fi

  # Use sqlite3 .backup command (handles WAL mode safely)
  if command -v sqlite3 &>/dev/null; then
    if sqlite3 "$db_path" ".backup '$backup_file'" 2>/dev/null; then
      # Verify backup integrity
      if verify_sqlite_backup "$backup_file"; then
        backup_success "SQLite: $db_path -> $backup_file"
        return 0
      else
        rm -f "$backup_file"
        backup_warning "SQLite backup verification failed, removed: $backup_file"
        return 1
      fi
    else
      backup_warning "SQLite backup failed for $db_path (using file copy fallback)"
    fi
  fi

  # Fallback to file copy if sqlite3 not available or failed
  if cp "$db_path" "$backup_file" 2>/dev/null; then
    # Verify backup integrity
    if verify_sqlite_backup "$backup_file"; then
      backup_success "SQLite (copy): $db_path -> $backup_file"
      return 0
    else
      rm -f "$backup_file"
      backup_warning "SQLite backup verification failed, removed: $backup_file"
      return 1
    fi
  fi

  backup_warning "Failed to backup SQLite: $db_path"
  return 1
}

# Backup PostgreSQL database
backup_postgres() {
  local url="$1"
  local backup_dir="$2"
  local timestamp="$3"

  if ! command -v pg_dump &>/dev/null; then
    backup_warning "pg_dump not found. Install PostgreSQL client tools to backup PostgreSQL."
    backup_info "  macOS: brew install postgresql"
    backup_info "  Ubuntu: apt install postgresql-client"
    return 1
  fi

  # Extract database name from URL
  local db_name
  db_name=$(echo "$url" | sed -E 's|.*/([^?]+).*|\1|')
  [[ -z "$db_name" ]] && db_name="postgres"

  local backup_file="$backup_dir/postgres/${db_name}-${timestamp}.sql.gz"
  mkdir -p "$backup_dir/postgres"

  # Run pg_dump with gzip compression
  export PGCONNECT_TIMEOUT=10
  if pg_dump "$url" 2>/dev/null | gzip > "$backup_file"; then
    # Check if backup is empty (connection may have failed silently)
    if [[ -s "$backup_file" ]]; then
      # Verify backup integrity
      if verify_postgres_backup "$backup_file"; then
        backup_success "PostgreSQL: $db_name -> $backup_file"
        return 0
      else
        rm -f "$backup_file"
        backup_warning "PostgreSQL backup verification failed, removed: $backup_file"
        return 1
      fi
    else
      rm -f "$backup_file"
      backup_warning "PostgreSQL backup is empty - connection may have failed"
      return 1
    fi
  fi

  rm -f "$backup_file"
  backup_warning "PostgreSQL backup failed for $db_name"
  return 1
}

# Backup MySQL database
backup_mysql() {
  local url="$1"
  local backup_dir="$2"
  local timestamp="$3"

  if ! command -v mysqldump &>/dev/null; then
    backup_warning "mysqldump not found. Install MySQL client tools to backup MySQL."
    backup_info "  macOS: brew install mysql-client"
    backup_info "  Ubuntu: apt install mysql-client"
    return 1
  fi

  # Parse URL using shared helper
  if ! parse_mysql_url "$url"; then
    backup_warning "Cannot parse MySQL URL format"
    return 1
  fi

  local backup_file="$backup_dir/mysql/${MYSQL_DB}-${timestamp}.sql.gz"
  mkdir -p "$backup_dir/mysql"

  # Run mysqldump with single-transaction for consistency
  if mysqldump \
      --host="$MYSQL_HOST" \
      --port="$MYSQL_PORT" \
      --user="$MYSQL_USER" \
      --password="$MYSQL_PASSWORD" \
      --single-transaction \
      --quick \
      --lock-tables=false \
      --connect-timeout=10 \
      "$MYSQL_DB" 2>/dev/null | gzip > "$backup_file"; then
    if [[ -s "$backup_file" ]]; then
      # Verify backup integrity
      if verify_mysql_backup "$backup_file"; then
        backup_success "MySQL: $MYSQL_DB -> $backup_file"
        return 0
      else
        rm -f "$backup_file"
        backup_warning "MySQL backup verification failed, removed: $backup_file"
        return 1
      fi
    fi
  fi

  rm -f "$backup_file"
  backup_warning "MySQL backup failed for $db_name"
  return 1
}

# Backup MongoDB database
backup_mongodb() {
  local url="$1"
  local backup_dir="$2"
  local timestamp="$3"

  if ! command -v mongodump &>/dev/null; then
    backup_warning "mongodump not found. Install MongoDB Database Tools to backup MongoDB."
    backup_info "  macOS: brew install mongodb-database-tools"
    backup_info "  Ubuntu: apt install mongodb-database-tools"
    return 1
  fi

  # Extract database name from URL
  local db_name
  db_name=$(echo "$url" | sed -E 's|.*/([^?]+).*|\1|')
  [[ -z "$db_name" ]] && db_name="mongodb"

  local backup_file="$backup_dir/mongodb/${db_name}-${timestamp}.gz"
  mkdir -p "$backup_dir/mongodb"

  # Run mongodump with archive and gzip
  if mongodump \
      --uri="$url" \
      --archive="$backup_file" \
      --gzip \
      --quiet \
      --serverSelectionTimeoutMS=10000 \
      2>/dev/null; then
    if [[ -s "$backup_file" ]]; then
      # Verify backup integrity
      if verify_mongodb_backup "$backup_file"; then
        backup_success "MongoDB: $db_name -> $backup_file"
        return 0
      else
        rm -f "$backup_file"
        backup_warning "MongoDB backup verification failed, removed: $backup_file"
        return 1
      fi
    fi
  fi

  rm -f "$backup_file"
  backup_warning "MongoDB backup failed for $db_name"
  return 1
}

# ============================================================================
# CLEANUP / ROTATION
# ============================================================================

# Clean up old backups, keeping max_backups per database name
cleanup_old_backups() {
  local backup_dir="$1"
  local max_backups="${2:-$DEFAULT_MAX_BACKUPS}"

  for subdir in sqlite postgres mysql mongodb; do
    local type_dir="$backup_dir/$subdir"
    [[ ! -d "$type_dir" ]] && continue

    # Get unique database names from backup files
    # Files are named: {dbname}-{YYYYMMDD-HHMMSS}.{ext}
    local db_names
    db_names=$(ls "$type_dir" 2>/dev/null | sed 's/-[0-9]\{8\}-[0-9]\{6\}\..*//' | sort -u)

    # Cleanup per database name
    while IFS= read -r db_name; do
      [[ -z "$db_name" ]] && continue

      # List backups for this specific DB, newest first, delete beyond limit
      ls -t "$type_dir/${db_name}"-* 2>/dev/null | tail -n +$((max_backups + 1)) | while read -r filepath; do
        rm -f "$filepath"
        backup_info "Removed old backup: $filepath"
      done
    done <<< "$db_names"
  done
}

# ============================================================================
# RESTORE FUNCTIONS
# ============================================================================

# Find original SQLite database path from backup filename
find_sqlite_target() {
  local db_name="$1"

  # Search for matching database file
  for ext in db sqlite sqlite3; do
    local found
    found=$(find . -maxdepth 4 -type f -name "${db_name}.${ext}" \
      -not -path "*/node_modules/*" \
      -not -path "*/.git/*" \
      -not -path "*/.backups/*" \
      2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
      echo "$found"
      return 0
    fi
  done
  return 1
}

# Restore SQLite database
restore_sqlite() {
  local backup_path="$1"
  local target="$2"

  # Create pre-restore backup
  if [[ -f "$target" ]]; then
    cp "$target" "${target}.pre-restore"
    print_info "Current database backed up to ${target}.pre-restore"
  fi

  if cp "$backup_path" "$target"; then
    print_success "Restored to $target"
    return 0
  fi

  print_error "Failed to restore to $target"
  return 1
}

# Restore PostgreSQL database
restore_postgres() {
  local backup_path="$1"

  local url
  url=$(detect_postgres) || {
    print_error "DATABASE_URL not found. Set it to restore PostgreSQL."
    return 1
  }

  if ! command -v psql &>/dev/null; then
    print_error "psql not found. Install PostgreSQL client tools to restore."
    return 1
  fi

  print_info "Restoring PostgreSQL from $backup_path..."

  if gunzip -c "$backup_path" | psql "$url" >/dev/null 2>&1; then
    print_success "PostgreSQL restored successfully"
    return 0
  fi

  print_error "PostgreSQL restore failed"
  return 1
}

# Restore MySQL database
restore_mysql() {
  local backup_path="$1"

  local url
  url=$(detect_mysql) || {
    print_error "MYSQL_URL not found. Set it to restore MySQL."
    return 1
  }

  if ! command -v mysql &>/dev/null; then
    print_error "mysql not found. Install MySQL client tools to restore."
    return 1
  fi

  # Parse URL using shared helper
  if ! parse_mysql_url "$url"; then
    print_error "Cannot parse MySQL URL"
    return 1
  fi

  print_info "Restoring MySQL from $backup_path..."

  if gunzip -c "$backup_path" | mysql \
      --host="$MYSQL_HOST" \
      --port="$MYSQL_PORT" \
      --user="$MYSQL_USER" \
      --password="$MYSQL_PASSWORD" \
      "$MYSQL_DB" 2>/dev/null; then
    print_success "MySQL restored successfully"
    return 0
  fi

  print_error "MySQL restore failed"
  return 1
}

# Restore MongoDB database
restore_mongodb() {
  local backup_path="$1"

  local url
  url=$(detect_mongodb) || {
    print_error "MONGODB_URL not found. Set it to restore MongoDB."
    return 1
  }

  if ! command -v mongorestore &>/dev/null; then
    print_error "mongorestore not found. Install MongoDB Database Tools to restore."
    return 1
  fi

  print_info "Restoring MongoDB from $backup_path..."

  if mongorestore \
      --uri="$url" \
      --archive="$backup_path" \
      --gzip \
      --drop \
      2>/dev/null; then
    print_success "MongoDB restored successfully"
    return 0
  fi

  print_error "MongoDB restore failed"
  return 1
}

# ============================================================================
# CLI ENTRY POINTS
# ============================================================================

# Main backup function
ralph_backup() {
  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet|-q)
        BACKUP_QUIET=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)

  # Ensure backup directory exists and is gitignored
  mkdir -p "$BACKUP_DIR/sqlite" "$BACKUP_DIR/postgres" "$BACKUP_DIR/mysql" "$BACKUP_DIR/mongodb"

  # Add to .gitignore if not present
  if [[ -f ".gitignore" ]]; then
    if ! grep -q "^\.backups/" ".gitignore" 2>/dev/null; then
      echo "" >> ".gitignore"
      echo "# Database backups (agentic-loop)" >> ".gitignore"
      echo ".backups/" >> ".gitignore"
    fi
  fi

  local backed_up=0
  local failed=0

  # Check database types in order of priority (only one type per project)
  # PostgreSQL/Supabase first (most common for production apps)
  local pg_url mysql_url mongo_url sqlite_files

  if pg_url=$(detect_postgres); then
    # PostgreSQL / Supabase
    if backup_postgres "$pg_url" "$BACKUP_DIR" "$timestamp"; then
      ((backed_up++))
    else
      ((failed++))
    fi
  elif mysql_url=$(detect_mysql); then
    # MySQL
    if backup_mysql "$mysql_url" "$BACKUP_DIR" "$timestamp"; then
      ((backed_up++))
    else
      ((failed++))
    fi
  elif mongo_url=$(detect_mongodb); then
    # MongoDB
    if backup_mongodb "$mongo_url" "$BACKUP_DIR" "$timestamp"; then
      ((backed_up++))
    else
      ((failed++))
    fi
  else
    # SQLite (fallback - local dev databases)
    sqlite_files=$(detect_sqlite)
    if [[ -n "$sqlite_files" ]]; then
      while IFS= read -r db_path; do
        [[ -z "$db_path" ]] && continue
        if backup_sqlite "$db_path" "$BACKUP_DIR" "$timestamp"; then
          ((backed_up++))
        else
          ((failed++))
        fi
      done <<< "$sqlite_files"
    fi
  fi

  # Cleanup old backups
  if [[ $backed_up -gt 0 ]]; then
    cleanup_old_backups "$BACKUP_DIR" "$DEFAULT_MAX_BACKUPS"
  fi

  # Summary
  if [[ $backed_up -eq 0 && $failed -eq 0 ]]; then
    backup_info "No databases detected for backup"
  elif [[ $failed -gt 0 ]]; then
    backup_warning "Backup completed: $backed_up succeeded, $failed failed"
  else
    backup_success "Backed up $backed_up database(s)"
  fi

  return 0
}

# List available backups
ralph_list_backups() {
  if [[ ! -d "$BACKUP_DIR" ]]; then
    print_info "No backups found. Run 'ralph backup' or commit to create backups."
    return 0
  fi

  echo ""
  print_info "=== Available Backups ==="
  echo ""

  local found=0

  for subdir in sqlite postgres mysql mongodb; do
    local type_dir="$BACKUP_DIR/$subdir"
    [[ ! -d "$type_dir" ]] && continue

    local files
    files=$(ls -t "$type_dir" 2>/dev/null)
    [[ -z "$files" ]] && continue

    # Capitalize first letter (bash 3.2 compatible)
    local label
    label=$(echo "$subdir" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    echo "$label:"

    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      local filepath="$type_dir/$file"
      local size
      size=$(get_file_size_mb "$filepath")
      [[ "$size" -eq 0 ]] && size="<1"

      # Extract timestamp from filename
      local ts
      ts=$(echo "$file" | grep -oE '[0-9]{8}-[0-9]{6}' | head -1)
      if [[ -n "$ts" ]]; then
        # Format: YYYYMMDD-HHMMSS -> YYYY-MM-DD HH:MM
        local formatted
        formatted=$(echo "$ts" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5/')
        echo "  $formatted - $file (${size}MB)"
      else
        echo "  $file (${size}MB)"
      fi

      ((found++))
    done <<< "$files"

    echo ""
  done

  if [[ $found -eq 0 ]]; then
    print_info "No backups found."
  else
    echo "Total: $found backup(s)"
    echo ""
    echo "Restore with: ralph restore <backup-path>"
  fi
}

# Restore from backup
ralph_restore() {
  local backup_path="${1:-}"
  local target="${2:-}"

  if [[ -z "$backup_path" ]]; then
    print_error "Usage: ralph restore <backup-path> [target]"
    print_info "Run 'ralph backups' to see available backups"
    return 1
  fi

  if [[ ! -f "$backup_path" ]]; then
    print_error "Backup file not found: $backup_path"
    return 1
  fi

  # Determine database type from path
  local db_type=""
  if [[ "$backup_path" == *"/sqlite/"* ]]; then
    db_type="sqlite"
  elif [[ "$backup_path" == *"/postgres/"* ]]; then
    db_type="postgres"
  elif [[ "$backup_path" == *"/mysql/"* ]]; then
    db_type="mysql"
  elif [[ "$backup_path" == *"/mongodb/"* ]]; then
    db_type="mongodb"
  else
    print_error "Cannot determine database type from path"
    return 1
  fi

  # For SQLite, find target if not specified
  if [[ "$db_type" == "sqlite" && -z "$target" ]]; then
    local db_name
    db_name=$(basename "$backup_path" | sed 's/-[0-9]\{8\}-[0-9]\{6\}\.db$//')
    target=$(find_sqlite_target "$db_name") || {
      print_error "Cannot find original database for '$db_name'"
      print_info "Specify target explicitly: ralph restore $backup_path <target-path>"
      return 1
    }
    print_info "Found matching database: $target"
  fi

  # Confirmation
  echo ""
  print_warning "WARNING: This will OVERWRITE the current database!"
  echo ""
  read -p "Type 'restore' to confirm: " confirm

  if [[ "$confirm" != "restore" ]]; then
    echo "Cancelled."
    return 1
  fi

  echo ""

  # Perform restore based on type
  case "$db_type" in
    sqlite)
      restore_sqlite "$backup_path" "$target"
      ;;
    postgres)
      restore_postgres "$backup_path"
      ;;
    mysql)
      restore_mysql "$backup_path"
      ;;
    mongodb)
      restore_mongodb "$backup_path"
      ;;
  esac
}
