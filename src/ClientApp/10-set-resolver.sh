#!/bin/sh
# Runs from /docker-entrypoint.d/ before nginx starts.
# nginx's `resolver` directive ignores /etc/resolv.conf, so hardcoding a DNS
# server breaks in any environment other than the one it was written for.
# Substitute the container's actual nameserver so the /api proxy works in
# Docker Compose and Kubernetes alike.
DNS_RESOLVER=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
sed -i "s|__DNS_RESOLVER__|${DNS_RESOLVER:-127.0.0.11}|" /etc/nginx/conf.d/default.conf
