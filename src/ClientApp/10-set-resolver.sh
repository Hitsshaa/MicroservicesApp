#!/bin/sh
# Runs from /docker-entrypoint.d/ before nginx starts.
# nginx's `resolver` directive ignores /etc/resolv.conf, so hardcoding a DNS
# server breaks in any environment other than the one it was written for.
# Substitute the container's actual nameserver so the /api proxy works in
# Docker Compose and Kubernetes alike.
DNS_RESOLVER=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
sed -i "s|__DNS_RESOLVER__|${DNS_RESOLVER:-127.0.0.11}|" /etc/nginx/conf.d/default.conf

# nginx's resolver also ignores resolv.conf *search domains*, so the bare
# service name "api-gateway" won't resolve in Kubernetes (curl works, nginx
# doesn't). Expand it to the namespace-qualified FQDN when we're in a pod;
# in Docker Compose the namespace file doesn't exist and the name stays bare.
NS_FILE=/var/run/secrets/kubernetes.io/serviceaccount/namespace
if [ -f "$NS_FILE" ]; then
    NS=$(cat "$NS_FILE")
    sed -i "s|http://api-gateway:5000|http://api-gateway.${NS}.svc.cluster.local:5000|" /etc/nginx/conf.d/default.conf
fi
