package config

import "os"

type Config struct {
	Env string
	HTTPAddr string
	DatabaseURL string
}

func Load() Config {
	cfg := Config{}
	cfg.Env = os.Getenv("APP_ENV")
	cfg.HTTPAddr = os.Getenv("HTTP_ADDR")
	cfg.DatabaseURL = os.Getenv("DATABASE_URL")
	if cfg.Env == "" { cfg.Env = "development" }
	if cfg.HTTPAddr == "" { cfg.HTTPAddr = ":8080" }
	return cfg
}
