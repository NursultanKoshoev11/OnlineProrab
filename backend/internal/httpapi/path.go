package httpapi

import "strings"

func resourceIDFromPath(path, prefix string) string {
	if !strings.HasPrefix(path, prefix) {
		return ""
	}
	id := strings.Trim(strings.TrimPrefix(path, prefix), "/")
	if strings.Contains(id, "/") {
		return ""
	}
	return id
}
