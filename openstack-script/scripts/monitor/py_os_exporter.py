#!/usr/bin/env python3
"""
Python OpenStack Exporter – enhanced version
Exposes these Gauges (scraped by Prometheus):

  openstack_service_up{service="nova-api"}            0/1
  openstack_instances_total                           total VMs
  openstack_instances{status="ACTIVE"}                VMs by status
  openstack_volumes_total                             total volumes
  openstack_volume_capacity_bytes{type="total|used"}  Cinder capacity (bytes)
  openstack_images_total                              total images
  openstack_projects_total                            total projects
"""

import time
import threading
import logging
from prometheus_client import start_http_server, Gauge
from openstack import connection

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

# ── OpenStack connection ────────────────────────────────────────────────────
# * region_name 可按实际环境调整 / 删除
# * verify=False 仅在自签证书环境下使用；正式环境应改为 CA 文件或删除
conn = connection.from_config(
    cloud="mycloud",
    region_name="RegionOne",
    verify=False,
)

# ── Prometheus metrics ─────────────────────────────────────────────────────
svc_up   = Gauge("openstack_service_up",
                 "Service health (1=OK)", ["service"])
inst_tot = Gauge("openstack_instances_total",
                 "Total instances in cloud")
inst_by  = Gauge("openstack_instances",
                 "Instances by status", ["status"])
vol_tot  = Gauge("openstack_volumes_total",
                 "Total Cinder volumes")
vol_cap  = Gauge("openstack_volume_capacity_bytes",
                 "Volume capacity in bytes", ["type"])  # total|used
img_tot  = Gauge("openstack_images_total",
                 "Total Glance images")
proj_tot = Gauge("openstack_projects_total",
                 "Total Keystone projects")

# ── Collect loop ───────────────────────────────────────────────────────────
def collect() -> None:
    while True:
        try:
            # 1) Service health-check
            for name, svc_type in {
                "nova-api":   "compute",
                "cinder-api": "volumev3",
                "glance-api": "image",
                "neutron-api": "network",
            }.items():
                try:
                    url = conn.session.get_endpoint(
                        service_type=svc_type,
                        interface="public",
                    )
                    ok = int(
                        conn.session.get(url, raise_exc=False, timeout=3).ok
                    ) if url else 0
                except Exception:
                    ok = 0
                svc_up.labels(service=name).set(ok)

            # 2) Instances
            servers = list(
                conn.compute.servers(all_projects=True)
            )
            inst_tot.set(len(servers))
            status_count = {}
            for s in servers:
                status_count[s.status] = status_count.get(s.status, 0) + 1
            for st, cnt in status_count.items():
                inst_by.labels(status=st).set(cnt)

            # 3) Volumes & capacity (use Cinder summary)
            summary = conn.block_storage.summary(all_projects=True)
            vol_tot.set(summary.total_count)
            vol_cap.labels(type="total").set(summary.total_size * 1024**3)
            vol_cap.labels(type="used").set(summary.total_consumed * 1024**3)

            # 4) Images & projects
            img_tot.set(
                len(list(conn.image.images(all_projects=True)))
            )
            proj_tot.set(
                len(list(conn.identity.projects(all_projects=True)))
            )

        except Exception as exc:  # unexpected error – keep exporter alive
            logging.warning("Collect error: %s", exc)

        time.sleep(30)

# ── Main ───────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    start_http_server(9184, addr="0.0.0.0")
    logging.info("Python OpenStack Exporter started on :9184")
    threading.Thread(target=collect, daemon=True).start()
    while True:
        time.sleep(3600)