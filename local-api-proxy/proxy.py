#!/usr/bin/env python3
"""
llmproxy - a tiny local reverse proxy for the Anthropic / Claude API.

Why: some agents inspect ANTHROPIC_BASE_URL to see which router/endpoint you
use. Point the agent at this proxy on localhost instead. The proxy keeps the
*real* upstream URL to itself and relays every request there, so the agent only
ever sees 127.0.0.1 and never learns your actual endpoint.

    agent  ->  http://127.0.0.1:8787  (this proxy)  ->  https://your-router

Usage:
    python3 proxy.py --upstream https://your-router.example.com
    # then, for the agent:
    export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"

Everything (method, path, query, headers, body, streaming SSE) is passed
through untouched, except:
  - the Host header is rewritten to the upstream host,
  - hop-by-hop headers are dropped,
  - if --api-key is given, the upstream credential is injected here so the
    agent never has to hold your real key either.

No third-party dependencies. Python 3.7+.
"""

import argparse
import http.server
import os
import socket
import sys
import threading
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

# Headers that are connection-specific and must not be forwarded verbatim.
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


def log(server, *args):
    if server.verbose:
        ts = time.strftime("%H:%M:%S")
        print(f"[{ts}]", *args, file=sys.stderr, flush=True)


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # --- silence the default noisy access log; we log ourselves when verbose.
    def log_message(self, fmt, *args):
        pass

    # every HTTP method funnels through the same relay
    def do_GET(self):
        self._relay()

    def do_POST(self):
        self._relay()

    def do_PUT(self):
        self._relay()

    def do_PATCH(self):
        self._relay()

    def do_DELETE(self):
        self._relay()

    def do_HEAD(self):
        self._relay()

    def do_OPTIONS(self):
        self._relay()

    # ------------------------------------------------------------------ relay
    def _read_request_body(self):
        length = self.headers.get("Content-Length")
        if length is not None:
            try:
                return self.rfile.read(int(length))
            except (ValueError, OSError):
                return b""
        # Chunked request bodies are rare from API clients, but handle them.
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            body = bytearray()
            while True:
                size_line = self.rfile.readline().strip()
                if not size_line:
                    break
                try:
                    size = int(size_line.split(b";")[0], 16)
                except ValueError:
                    break
                if size == 0:
                    self.rfile.readline()  # trailing CRLF
                    break
                body += self.rfile.read(size)
                self.rfile.readline()  # CRLF after each chunk
            return bytes(body)
        return None

    def _build_upstream_headers(self):
        srv = self.server
        headers = {}
        for key in self.headers.keys():
            if key.lower() in HOP_BY_HOP or key.lower() == "host":
                continue
            headers[key] = self.headers[key]
        # Point the request at the real host.
        headers["Host"] = srv.upstream.netloc
        # Optionally inject the upstream credential so the agent never holds it.
        if srv.api_key:
            headers["x-api-key"] = srv.api_key
            headers["Authorization"] = f"Bearer {srv.api_key}"
        return headers

    def _upstream_url(self):
        base = self.server.upstream
        # self.path already contains the leading slash + query string.
        prefix = base.path.rstrip("/")
        return f"{base.scheme}://{base.netloc}{prefix}{self.path}"

    def _relay(self):
        srv = self.server
        url = self._upstream_url()
        body = self._read_request_body()
        headers = self._build_upstream_headers()

        log(srv, f"{self.command} {self.path} -> {url}")

        req = urllib.request.Request(
            url, data=body, headers=headers, method=self.command
        )
        try:
            # timeout=None: streaming/SSE responses can idle between events.
            resp = urllib.request.urlopen(req, timeout=None)
        except urllib.error.HTTPError as e:
            # An HTTPError is itself a valid response (4xx/5xx) - forward it.
            resp = e
        except (urllib.error.URLError, OSError) as e:
            log(srv, f"upstream error: {e}")
            self.close_connection = True
            try:
                self.send_error(502, "Bad Gateway", str(e))
            except OSError:
                pass
            return

        try:
            self._forward_response(resp)
        finally:
            try:
                resp.close()
            except Exception:
                pass

    def _forward_response(self, resp):
        status = getattr(resp, "status", None) or resp.getcode()
        resp_headers = resp.headers
        content_length = resp_headers.get("Content-Length")
        streaming = content_length is None and self.command != "HEAD"

        self.send_response_only(status)
        for key, value in resp_headers.items():
            lk = key.lower()
            if lk in HOP_BY_HOP or lk == "content-length":
                continue
            self.send_header(key, value)
        if self.command == "HEAD":
            if content_length is not None:
                self.send_header("Content-Length", content_length)
            self.end_headers()
            return
        if streaming:
            # Unknown length (SSE): re-frame as chunked so we can flush live.
            self.send_header("Transfer-Encoding", "chunked")
        else:
            self.send_header("Content-Length", content_length)
        self.end_headers()

        try:
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                if streaming:
                    self.wfile.write(f"{len(chunk):X}\r\n".encode("ascii"))
                    self.wfile.write(chunk)
                    self.wfile.write(b"\r\n")
                else:
                    self.wfile.write(chunk)
                self.wfile.flush()
            if streaming:
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            # Client (agent) hung up mid-stream; nothing more to do.
            self.close_connection = True


class ThreadingHTTPServer(
    http.server.ThreadingHTTPServer if hasattr(http.server, "ThreadingHTTPServer")
    else http.server.HTTPServer
):
    daemon_threads = True
    # Give SSE streams room; don't block the whole server on one slow client.
    allow_reuse_address = True


def parse_args(argv):
    p = argparse.ArgumentParser(
        prog="llmproxy",
        description="Tiny local reverse proxy that hides your real API endpoint "
        "from the agent.",
    )
    p.add_argument(
        "--upstream",
        default=os.environ.get("LLMPROXY_UPSTREAM", "https://api.anthropic.com"),
        help="Real upstream base URL to relay to (env: LLMPROXY_UPSTREAM). "
        "Default: https://api.anthropic.com",
    )
    p.add_argument(
        "--host",
        default=os.environ.get("LLMPROXY_HOST", "127.0.0.1"),
        help="Local address to bind (env: LLMPROXY_HOST). Default: 127.0.0.1",
    )
    p.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("LLMPROXY_PORT", "8787")),
        help="Local port to listen on (env: LLMPROXY_PORT). Default: 8787",
    )
    p.add_argument(
        "--api-key",
        default=os.environ.get("LLMPROXY_API_KEY"),
        help="Optional upstream API key to inject here (env: LLMPROXY_API_KEY). "
        "If set, the agent doesn't need to hold your real key.",
    )
    p.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Log each proxied request to stderr.",
    )
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])

    upstream = urlsplit(args.upstream)
    if upstream.scheme not in ("http", "https") or not upstream.netloc:
        print(
            f"error: --upstream must be a full http(s) URL, got {args.upstream!r}",
            file=sys.stderr,
        )
        return 2

    httpd = ThreadingHTTPServer((args.host, args.port), ProxyHandler)
    httpd.upstream = upstream
    httpd.api_key = args.api_key
    httpd.verbose = args.verbose

    print(
        f"llmproxy: http://{args.host}:{args.port}  ->  "
        f"{upstream.scheme}://{upstream.netloc}{upstream.path.rstrip('/')}",
        file=sys.stderr,
    )
    print(
        f"point your agent at:  export ANTHROPIC_BASE_URL=\"http://{args.host}:{args.port}\"",
        file=sys.stderr,
    )
    if args.api_key:
        print("upstream API key: injected by proxy (agent does not need it)",
              file=sys.stderr)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down", file=sys.stderr)
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
