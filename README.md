curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/server-config.conf \
    -o /tmp/server-config.conf && \
curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/domains.csv \
    -o /tmp/domains.csv && \
bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/QuicCloud-Bulk-Link/main/quiccloud-bulk-link.sh)
