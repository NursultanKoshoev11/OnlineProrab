package config

import "os"

type Config struct {
	Env string
	HTTPAddr string
	DatabaseURL string
}

func Load() Config {
	return Config{
		Env: getEnv("APP_ENV", "development"),
		HTTPAddr: getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL: getEnv("DATABASE_URL", ""),
	}
}

func getEnv(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
	