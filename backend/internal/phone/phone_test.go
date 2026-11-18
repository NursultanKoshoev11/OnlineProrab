package phone

import "testing"

func TestNormalizeProducesOneCanonicalForm(t *testing.T) {
	for input, want := range map[string]string{
		"+996700000000":      "+996700000000",
		"996700000000":       "+996700000000",
		" +996 700 000 000 ": "+996700000000",
		"+996-700-000-000":   "+996700000000",
		"(996) 700.000.000":  "+996700000000",
		"996 700000000": "+996700000000",
		"":                   "",
		"+":                  "+",
		"++996700000000":     "++996700000000",
		"99670000000a":       "99670000000a",
	} {
		if got := Normalize(input); got != want {
			t.Errorf("Normalize(%q) = %q, want %q", input, got, want)
		}
	}
}
