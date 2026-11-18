// Package phone holds the single canonical phone-number format used for
// accounts, invitations, rate limits and configuration.
package phone

import "strings"

// Normalize returns the canonical "+<digits>" form of a phone number.
// Spaces, dashes, dots and parentheses are removed and a missing leading "+"
// is added, so "+996 700 000 000", "996700000000" and "+996-700-000-000"
// all identify the same account. Input that is not a plausible number is
// returned stripped but otherwise unchanged so validation can reject it.
func Normalize(value string) string {
	var builder strings.Builder
	builder.Grow(len(value) + 1)
	for _, ch := range strings.TrimSpace(value) {
		switch ch {
		case ' ', '\t', '-', '.', '(', ')', ' ':
			continue
		}
		builder.WriteRune(ch)
	}
	cleaned := builder.String()
	digits := strings.TrimPrefix(cleaned, "+")
	if digits == "" || strings.HasPrefix(digits, "+") {
		return cleaned
	}
	for _, ch := range digits {
		if ch < '0' || ch > '9' {
			return cleaned
		}
	}
	return "+" + digits
}
