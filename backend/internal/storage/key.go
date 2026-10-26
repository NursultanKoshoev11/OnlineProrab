package storage

import (
	"fmt"
	"path"
	"strings"
)

func cleanKey(key string) (string, error) {
	if key == "" || strings.ContainsRune(key, '\x00') || strings.Contains(key, "\\") || strings.HasPrefix(key, "/") {
		return "", fmt.Errorf("invalid object key")
	}
	if path.Clean(key) != key || key == "." {
		return "", fmt.Errorf("invalid object key")
	}
	for _, segment := range strings.Split(key, "/") {
		if segment == "" || segment == "." || segment == ".." {
			return "", fmt.Errorf("invalid object key")
		}
	}
	return key, nil
}
