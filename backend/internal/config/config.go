package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	Env          string
	HTTPAddr     string
	DatabaseURL  string
	JWTSecret    string
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
	IdleTimeout  time.Duration
}

func Load() Config {
	return Config{
		Env:          getEnv("APP_ENV", "development"),
		HTTPAddr:     getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL:  getEnv("DATABASE_URL", "postgres://online