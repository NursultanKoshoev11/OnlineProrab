package database

import (
	"io/fs"
	"testing"
)

func TestMigrationVersion(t *testing.T) {
	version, err := migrationVersion("000002_harden_existing_schema.up.sql")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if version != 2 {
		t.Fatalf("expected version 2, got %d", version)
	}
}

func TestMigrationVersionRejectsInvalidFilename(t *testing.T) {
	cases := []string{
		"invalid.sql",
		"abc_initial.up.sql",
		"000000_initial.up.sql",
	}
	for _, name := range cases {
		if _, err := migrationVersion(name); err == nil {
			t.Fatalf("expected %q to be rejected", name)
		}
	}
}

func TestMigrationVersionsAreUnique(t *testing.T) {
	entries, err := fs.ReadDir(migrationFiles, "migrations")
	if err != nil {
		t.Fatalf("read migration filenames: %v", err)
	}
	seen := make(map[int64]string)
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		version, err := migrationVersion(entry.Name())
		if err != nil {
			t.Fatalf("invalid migration filename %q: %v", entry.Name(), err)
		}
		if previous, exists := seen[version]; exists {
			t.Fatalf("migrations %q and %q share version %d", previous, entry.Name(), version)
		}
		seen[version] = entry.Name()
	}
}
