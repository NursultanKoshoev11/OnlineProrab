package httpapi

import (
	"context"
	"testing"
)

func TestCanonicalPhoneMigrationConvertsOnlyUnambiguousRows(t *testing.T) {
	db := openMigratedTestDB(t)
	ctx := context.Background()
	if _, err := db.Pool.Exec(ctx, `DELETE FROM schema_migrations WHERE version = 34`); err != nil {
		t.Fatalf("forget migration 34: %v", err)
	}
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO users (phone) VALUES
			('996700000701'),          -- plain digits: converted
			('+996 700 000 702'),      -- spaced: converted
			('996700000703'),          -- collides with the next row: both kept
			('+996700000703'),
			('+996700000704'),         -- already canonical
			('not-a-phone')            -- invalid: untouched
	`); err != nil {
		t.Fatalf("seed users: %v", err)
	}
	if err := db.ApplyMigrations(ctx); err != nil {
		t.Fatalf("re-apply migrations: %v", err)
	}
	rows, err := db.Pool.Query(ctx, `SELECT phone FROM users ORDER BY phone`)
	if err != nil {
		t.Fatalf("load phones: %v", err)
	}
	defer rows.Close()
	var got []string
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			t.Fatalf("scan phone: %v", err)
		}
		got = append(got, value)
	}
	want := []string{"+996700000701", "+996700000702", "+996700000703", "+996700000704", "996700000703", "not-a-phone"}
	if len(got) != len(want) {
		t.Fatalf("phones = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("phones = %v, want %v", got, want)
		}
	}
}
