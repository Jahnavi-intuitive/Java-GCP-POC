# Load-ready profile: projected for 10,000 concurrent users (~5,000 req/s).
# Based on measured ~100-120 req/s per 1-vCPU instance at ~60% CPU.
# NOT applied by default (cost). Use: terraform apply -var-file=profiles/load-ready.tfvars
max_instances = 60
db_tier       = "db-custom-4-15360"