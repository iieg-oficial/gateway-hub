#!/usr/bin/env python3
"""
Stress test multi-IP — MapaLab

Simula usuarios desde multiples IPs para medir la capacidad real del servidor
sin que el rate limiting por IP sea el cuello de botella.

Uso:
  python stress_test_multi_ip.py --env local --ips 10 --users 200
  python stress_test_multi_ip.py --env staging --ips 20 --users 300 --ramp-steps 6
  python stress_test_multi_ip.py --env production --ips 50 --users 500

Requisito:
  Nginx debe confiar en X-Forwarded-For desde la IP del cliente de pruebas.
  En local (Docker), agregar temporalmente a nginx.conf:

    set_real_ip_from 172.16.0.0/12;   # Docker networks
    set_real_ip_from 127.0.0.0/8;     # localhost

  O ejecutar desde una maquina en la subred 10.13.128.0/24 (ya confiada).
  Despues de las pruebas, REMOVER las lineas agregadas.

Como funciona:
  - Genera N IPs simuladas (10.200.x.y)
  - Distribuye usuarios entre las IPs (round-robin)
  - Cada request incluye X-Forwarded-For con la IP asignada
  - Nginx usa esa IP para rate limiting ($binary_remote_addr)
  - Resultado: cada "IP" tiene su propio bucket de rate limit

Comparacion con stress_test.py (single-IP):
  - stress_test.py:          100 usuarios, 1 IP  → todos comparten 10r/s
  - stress_test_multi_ip.py: 100 usuarios, 10 IPs → cada grupo de 10 tiene 10r/s = 100r/s total
"""

import asyncio
import aiohttp
import argparse
import os
import random
import re
import statistics
import time
from collections import defaultdict
from datetime import datetime
from urllib.parse import urljoin, urlparse

ENVS = {
    "local": {
        "url": "https://localhost/mapalab/mapa",
        "ssl": False,
    },
    "staging": {
        "url": os.environ.get("STRESS_TEST_STAGING_URL", ""),
        "ssl": True,
    },
    "production": {
        "url": os.environ.get("STRESS_TEST_PRODUCTION_URL", ""),
        "ssl": True,
    },
}

URL = ""
BASE_URL = ""
SSL_VERIFY = True

TIMEOUT = aiohttp.ClientTimeout(total=30, connect=10)

BREAK_ERROR_RATE = 30.0
BREAK_P95_MS = 4_000


def configure_target(env: str, url: str):
    global URL, BASE_URL, SSL_VERIFY

    if url:
        URL = url
    elif env and env in ENVS:
        cfg = ENVS[env]
        URL = cfg["url"]
        SSL_VERIFY = cfg["ssl"]
    else:
        URL = ENVS["local"]["url"]
        SSL_VERIFY = False

    if not URL:
        print(f"\n  Error: No hay URL para el entorno '{env}'.")
        print(f"  Configura la variable de entorno STRESS_TEST_{env.upper()}_URL")
        print(f"  o usa --url para pasar la URL directamente.\n")
        raise SystemExit(1)

    parsed = urlparse(URL)
    BASE_URL = f"{parsed.scheme}://{parsed.netloc}"


def generate_ips(count: int) -> list[str]:
    ips = []
    for i in range(count):
        octet3 = (i // 254) + 1
        octet4 = (i % 254) + 1
        ips.append(f"10.200.{octet3}.{octet4}")
    return ips


def make_headers_page(forwarded_ip: str) -> dict:
    return {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "es-MX,es;q=0.8,en-US;q=0.5",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
        "Upgrade-Insecure-Requests": "1",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "none",
        "X-Forwarded-For": forwarded_ip,
    }


def make_headers_asset(forwarded_ip: str) -> dict:
    return {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept": "*/*",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
        "X-Forwarded-For": forwarded_ip,
    }


def extract_assets(html: str) -> list[str]:
    assets = []
    base_host = urlparse(BASE_URL).netloc
    patterns = [
        r'<link[^>]+href=["\']([^"\']+\.css(?:\?[^"\']*)?)["\']',
        r'<script[^>]+src=["\']([^"\']+\.js(?:\?[^"\']*)?)["\']',
    ]
    for pat in patterns:
        for m in re.finditer(pat, html, re.IGNORECASE):
            url = urljoin(BASE_URL, m.group(1))
            if urlparse(url).netloc == base_host:
                assets.append(url)
    return assets[:25]


async def real_user_session(connector, forwarded_ip: str):
    result = {
        "ip": forwarded_ip,
        "page_status": None,
        "page_elapsed": 0.0,
        "work_elapsed": 0.0,
        "assets_ok": 0,
        "assets_fail": 0,
        "error": None,
        "success": False,
    }

    jar = aiohttp.CookieJar(unsafe=True)
    async with aiohttp.ClientSession(
        connector=connector, connector_owner=False, cookie_jar=jar
    ) as session:
        t0 = time.perf_counter()
        try:
            async with session.get(
                URL, headers=make_headers_page(forwarded_ip), timeout=TIMEOUT
            ) as resp:
                result["page_status"] = resp.status
                html = await resp.text(errors="replace")
        except asyncio.TimeoutError:
            result["error"] = "TIMEOUT"
            result["page_elapsed"] = time.perf_counter() - t0
            return result
        except aiohttp.ClientConnectorError:
            result["error"] = "CONNECTION_ERROR"
            result["page_elapsed"] = time.perf_counter() - t0
            return result
        except Exception as e:
            result["error"] = type(e).__name__
            result["page_elapsed"] = time.perf_counter() - t0
            return result

        result["page_elapsed"] = time.perf_counter() - t0

        if not (result["page_status"] and 200 <= result["page_status"] < 400):
            return result

        assets = extract_assets(html)

        async def fetch_asset(asset_url):
            try:
                async with session.get(
                    asset_url,
                    headers=make_headers_asset(forwarded_ip),
                    timeout=TIMEOUT,
                ) as r:
                    await r.read()
                    return r.status < 400
            except Exception:
                return False

        if assets:
            asset_results = await asyncio.gather(*[fetch_asset(u) for u in assets])
            result["assets_ok"] = sum(1 for r in asset_results if r)
            result["assets_fail"] = sum(1 for r in asset_results if not r)

        result["success"] = True
        result["work_elapsed"] = time.perf_counter() - t0

        await asyncio.sleep(random.uniform(1.0, 3.0))

    return result


async def user_worker(
    worker_id, connector, start_barrier, stop_event, bucket, forwarded_ip, sessions_per_user=1
):
    await start_barrier.wait()
    for _ in range(sessions_per_user):
        if stop_event.is_set():
            break
        r = await real_user_session(connector, forwarded_ip)
        bucket.append(r)


def analyze_snapshot(bucket, current_users, elapsed, num_ips):
    ok = [r for r in bucket if r["success"]]
    failed = [r for r in bucket if not r["success"]]
    times = [r["page_elapsed"] for r in ok]
    total = len(bucket)

    status_counts = defaultdict(int)
    error_counts = defaultdict(int)
    for r in bucket:
        if r["page_status"]:
            status_counts[r["page_status"]] += 1
        if r["error"]:
            error_counts[r["error"]] += 1

    error_rate = len(failed) / total * 100 if total else 0.0

    sorted_times = sorted(times)

    def pct(p):
        if len(sorted_times) < 2:
            return None
        return sorted_times[int(len(sorted_times) * p)] * 1000

    p95 = pct(0.95)

    total_work_s = sum(r["work_elapsed"] for r in ok)
    server_rps = len(ok) / total_work_s * current_users if total_work_s > 0 else 0.0

    is_breaking = error_rate > BREAK_ERROR_RATE or (p95 is not None and p95 > BREAK_P95_MS)

    ip_stats = defaultdict(lambda: {"ok": 0, "fail": 0, "rate_limited": 0})
    for r in bucket:
        ip = r["ip"]
        if r["success"]:
            ip_stats[ip]["ok"] += 1
        else:
            ip_stats[ip]["fail"] += 1
        if r["page_status"] == 429:
            ip_stats[ip]["rate_limited"] += 1

    return {
        "users": current_users,
        "num_ips": num_ips,
        "users_per_ip": current_users // num_ips,
        "total": total,
        "ok": len(ok),
        "errors": len(failed),
        "error_rate": error_rate,
        "elapsed": elapsed,
        "rps_load": total / elapsed if elapsed > 0 else 0,
        "server_rps": server_rps,
        "avg_ms": statistics.mean(times) * 1000 if times else None,
        "median_ms": statistics.median(times) * 1000 if times else None,
        "p90_ms": pct(0.90),
        "p95_ms": p95,
        "p99_ms": pct(0.99),
        "min_ms": min(times) * 1000 if times else None,
        "max_ms": max(times) * 1000 if times else None,
        "status_counts": dict(status_counts),
        "error_counts": dict(error_counts),
        "ip_stats": dict(ip_stats),
        "is_breaking": is_breaking,
    }


def print_snapshot(s, label=""):
    sep = "─" * 70
    tag = "QUIEBRE" if s["is_breaking"] else "ESTABLE"
    print(sep)
    if label:
        print(f"  {label}")
    print(
        f"  {tag}  |  {s['users']:>4} usuarios  |  {s['num_ips']} IPs ({s['users_per_ip']} usr/IP)"
        f"  |  {s['total']:>5} sesiones  |  {s['elapsed']:.1f}s"
    )
    print(f"  OK: {s['ok']:>5}   Errores: {s['errors']:>5}   Error rate: {s['error_rate']:.1f}%")
    print(f"  RPS carga: {s['rps_load']:.2f}  |  RPS servidor (real): {s['server_rps']:.2f}")
    if s["avg_ms"] is not None:

        def fmt(v):
            return f"{v:.0f}ms" if v is not None else "N/A"

        print(
            f"  Latencia -> Avg: {fmt(s['avg_ms'])}  "
            f"Med: {fmt(s['median_ms'])}  "
            f"p90: {fmt(s['p90_ms'])}  "
            f"p95: {fmt(s['p95_ms'])}  "
            f"p99: {fmt(s['p99_ms'])}"
        )
    else:
        print("  Sin respuestas exitosas para calcular latencias.")
    if s["status_counts"]:
        codes = "  ".join(f"HTTP {k}: {v}" for k, v in sorted(s["status_counts"].items()))
        print(f"  Codigos HTTP -> {codes}")
    if s["error_counts"]:
        errs = "  ".join(f"{k}: {v}" for k, v in s["error_counts"].items())
        print(f"  Errores      -> {errs}")

    rate_limited_ips = {
        ip: stats
        for ip, stats in s["ip_stats"].items()
        if stats["rate_limited"] > 0
    }
    if rate_limited_ips:
        print(f"  IPs con rate limit (429): {len(rate_limited_ips)}/{s['num_ips']}")
    else:
        print(f"  Rate limit: ninguna IP alcanzo el limite")


def print_final_report(snapshots, num_ips):
    stable = [s for s in snapshots if not s["is_breaking"]]
    breaking = next((s for s in snapshots if s["is_breaking"]), None)

    print(f"\n{'=' * 70}")
    print(f"  RESUMEN FINAL — {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  URL: {URL}")
    print(f"  IPs simuladas: {num_ips}")
    print(f"{'─' * 70}")
    print(f"  Criterios de quiebre: error rate > {BREAK_ERROR_RATE}%  |  p95 > {BREAK_P95_MS} ms")
    print(f"{'─' * 70}")

    if stable:
        last = stable[-1]
        best_server = max(stable, key=lambda x: x["server_rps"])
        p95_str = f"{last['p95_ms']:.0f}ms" if last["p95_ms"] else "N/A"
        print(
            f"  Ultima fase estable     : {last['users']:>4} usuarios ({last['users_per_ip']} por IP)  "
            f"error {last['error_rate']:.1f}%  p95 {p95_str}"
        )
        print(
            f"  Max RPS servidor (real) : {best_server['server_rps']:.2f} rps  "
            f"@ {best_server['users']} usuarios"
        )
    else:
        print("  El servidor no soporto ni la carga inicial.")

    if breaking:
        p95_str = f"{breaking['p95_ms']:.0f}ms" if breaking["p95_ms"] else "N/A"
        print(
            f"  Punto de quiebre        : {breaking['users']:>4} usuarios ({breaking['users_per_ip']} por IP)  "
            f"error {breaking['error_rate']:.1f}%  p95 {p95_str}"
        )

        total_429 = breaking["status_counts"].get(429, 0)
        total_5xx = sum(v for k, v in breaking["status_counts"].items() if 500 <= k < 600)
        if total_429 > total_5xx:
            print(f"  Tipo de quiebre: rate limiting ({total_429} x 429)")
        elif total_5xx > 0:
            print(f"  Tipo de quiebre: saturacion del backend ({total_5xx} x 5xx)")
        else:
            print(f"  Tipo de quiebre: errores de conexion/timeout")
    else:
        last_users = snapshots[-1]["users"] if snapshots else 0
        print(f"  No se alcanzo el quiebre (max probado: {last_users} usuarios)")

    print(f"\n  Interpretacion:")
    print(f"  - Con 1 IP:  el rate limit (10r/s) frena a ~100-120 usuarios")
    print(f"  - Con {num_ips} IPs: el rate limit efectivo es {num_ips}x = ~{num_ips * 10}r/s")
    print(f"  - Si el quiebre es por 5xx/timeout: el backend es el limite real")
    print(f"  - Si el quiebre es por 429: aun hay capacidad de backend sin usar")
    print(f"{'=' * 70}\n")


async def run_ramp(max_users, ramp_steps, num_ips, sessions_per_user):
    step_size = max(1, max_users // ramp_steps)
    ips = generate_ips(num_ips)

    print(f"\n{'=' * 70}")
    print(f"  MODO RAMPA MULTI-IP: {ramp_steps} pasos — hasta {max_users} usuarios")
    print(f"  IPs simuladas: {num_ips} — usuarios por IP: ~{max_users // num_ips}")
    print(f"  Sesiones por usuario: {sessions_per_user}")
    print(f"  Rate limit efectivo: ~{num_ips * 10}r/s general, ~{num_ips * 50}r/s static")
    print(f"  Quiebre si: error rate > {BREAK_ERROR_RATE}%  o  p95 > {BREAK_P95_MS} ms")
    print(f"{'=' * 70}\n")

    snapshots = []

    for step in range(ramp_steps):
        concurrent = min(step_size * (step + 1), max_users)
        connector = aiohttp.TCPConnector(ssl=SSL_VERIFY, limit=concurrent * 15)
        start_barrier = asyncio.Event()
        stop_event = asyncio.Event()
        bucket = []

        tasks = [
            asyncio.create_task(
                user_worker(
                    i, connector, start_barrier, stop_event, bucket,
                    forwarded_ip=ips[i % num_ips],
                    sessions_per_user=sessions_per_user,
                )
            )
            for i in range(concurrent)
        ]

        total_sesiones = concurrent * sessions_per_user
        print(
            f"  Paso {step + 1}/{ramp_steps}: {concurrent} usuarios / {num_ips} IPs "
            f"({concurrent // num_ips} usr/IP) x {sessions_per_user} sesion(es) = {total_sesiones} sesiones ...",
            flush=True,
        )
        step_start = time.perf_counter()
        start_barrier.set()

        await asyncio.gather(*tasks, return_exceptions=True)
        elapsed = time.perf_counter() - step_start
        await connector.close()

        snap = analyze_snapshot(bucket, concurrent, elapsed, num_ips)
        snapshots.append(snap)
        tag = "QUIEBRE" if snap["is_breaking"] else "OK"
        print(f"   {tag}  {snap['ok']}/{total_sesiones} OK  error {snap['error_rate']:.1f}%  {elapsed:.1f}s")
        print_snapshot(snap, label=f"Paso {step + 1} — {concurrent} usuarios / {num_ips} IPs")

        if snap["is_breaking"]:
            print(f"\n  Quiebre detectado en {concurrent} usuarios. Prueba finalizada.")
            break

        await asyncio.sleep(2)

    print_final_report(snapshots, num_ips)


async def run_fixed(users, num_ips, sessions_per_user):
    ips = generate_ips(num_ips)
    total_sesiones = users * sessions_per_user

    print(f"\n{'=' * 70}")
    print(f"  MODO FIJO MULTI-IP: {users} usuarios / {num_ips} IPs ({users // num_ips} usr/IP)")
    print(f"  Sesiones: {total_sesiones} total")
    print(f"  Rate limit efectivo: ~{num_ips * 10}r/s general, ~{num_ips * 50}r/s static")
    print(f"  Quiebre si: error rate > {BREAK_ERROR_RATE}%  o  p95 > {BREAK_P95_MS} ms")
    print(f"{'=' * 70}\n")

    connector = aiohttp.TCPConnector(ssl=SSL_VERIFY, limit=users * 15)
    start_barrier = asyncio.Event()
    stop_event = asyncio.Event()
    bucket = []

    tasks = [
        asyncio.create_task(
            user_worker(
                i, connector, start_barrier, stop_event, bucket,
                forwarded_ip=ips[i % num_ips],
                sessions_per_user=sessions_per_user,
            )
        )
        for i in range(users)
    ]

    print(f"  Lanzando {users} usuarios ({users // num_ips} por IP)...")
    start_time = time.perf_counter()
    start_barrier.set()

    await asyncio.gather(*tasks, return_exceptions=True)
    await connector.close()

    elapsed = time.perf_counter() - start_time
    final_snap = analyze_snapshot(bucket, users, elapsed, num_ips)
    print_snapshot(final_snap, label=f"Resultado — {users} usuarios / {num_ips} IPs")
    print_final_report([final_snap], num_ips)


def main():
    parser = argparse.ArgumentParser(
        description="Stress test multi-IP para medir capacidad real del servidor"
    )
    parser.add_argument(
        "--env", choices=["local", "staging", "production"], default="local",
        help="Entorno objetivo (default: local)",
    )
    parser.add_argument("--url", type=str, default="", help="URL custom (sobreescribe --env)")
    parser.add_argument(
        "--mode", choices=["fixed", "ramp"], default="ramp",
        help="fixed: N usuarios fijos  |  ramp: incremento gradual (default: ramp)",
    )
    parser.add_argument("--users", type=int, default=200, help="Usuarios concurrentes (default: 200)")
    parser.add_argument("--ips", type=int, default=10, help="IPs simuladas (default: 10)")
    parser.add_argument("--ramp-steps", type=int, default=5, help="Pasos de rampa (default: 5)")
    parser.add_argument("--sessions", type=int, default=1, help="Sesiones por usuario (default: 1)")
    args = parser.parse_args()

    if args.users < args.ips:
        print(f"\n  Error: --users ({args.users}) debe ser >= --ips ({args.ips})\n")
        raise SystemExit(1)

    configure_target(args.env, args.url)

    print(f"\n  Iniciando prueba multi-IP: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Entorno: {args.env}  |  SSL verify: {SSL_VERIFY}")
    print(f"  Target: {URL}")
    print(f"  IPs simuladas: {args.ips}  |  Usuarios: {args.users}  |  Por IP: {args.users // args.ips}")

    if args.mode == "ramp":
        asyncio.run(run_ramp(args.users, args.ramp_steps, args.ips, args.sessions))
    else:
        asyncio.run(run_fixed(args.users, args.ips, args.sessions))


if __name__ == "__main__":
    main()
