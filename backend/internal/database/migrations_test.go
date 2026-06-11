package database

import "testing"

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
