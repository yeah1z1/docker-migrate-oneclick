from pathlib import Path


script = Path("docker-migrate.sh").read_text(encoding="utf-8")
marker = "  cat > \"$web_app\" <<'PYWEB_EOF'"
start = script.index(marker)
start = script.index("\n", start) + 1
end = script.index("\nPYWEB_EOF", start)
compile(script[start:end], "embedded-web-console.py", "exec")
