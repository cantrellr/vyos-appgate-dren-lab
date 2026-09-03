“Ready” confirms the J52 cluster bootstrapped successfully, but verify the live WAL stream from both sides.

First run the repository validation:

```bash
./scripts/deploy-platform.sh validate-identity-ha
```

Then identify the database pods:

```bash
J64_POD="$(kubectl --context j64seg1opdev -n oppostgres \
  get pods -l 'cnpg.io/cluster=oppostgres-opkeycloak-db,role=primary' \
  -o jsonpath='{.items[0].metadata.name}')"

J52_POD="$(kubectl --context j52seg1opdev -n oppostgres \
  get pods -l 'cnpg.io/cluster=oppostgres-opkeycloak-db,role=primary' \
  -o jsonpath='{.items[0].metadata.name}')"

echo "J64: $J64_POD"
echo "J52: $J52_POD"
```

### Verify J52 is receiving and replaying WAL

```bash
kubectl --context j52seg1opdev -n oppostgres exec "$J52_POD" -- \
  psql -U postgres -d postgres -P pager=off -x -c "
SELECT
  pg_is_in_recovery() AS is_replica,
  pg_last_wal_receive_lsn() AS received_lsn,
  pg_last_wal_replay_lsn() AS replayed_lsn,
  pg_size_pretty(
    pg_wal_lsn_diff(
      pg_last_wal_receive_lsn(),
      pg_last_wal_replay_lsn()
    )
  ) AS local_replay_queue;
SELECT
  status,
  sender_host,
  sender_port,
  slot_name,
  latest_end_lsn,
  clock_timestamp() - last_msg_receipt_time AS message_age
FROM pg_stat_wal_receiver;"
```

Expected:

| Field                | Healthy result                                       |
| -------------------- | ---------------------------------------------------- |
| `is_replica`         | `t`                                                  |
| `status`             | `streaming`                                          |
| `sender_host`        | `j64seg1opdev-postgres-repl.dev.kube` or `1.0.0.216` |
| `local_replay_queue` | Usually `0 bytes` or low                             |
| `message_age`        | Usually seconds, not continuously increasing         |

### Verify J64 sees the replication connection

```bash
kubectl --context j64seg1opdev -n oppostgres exec "$J64_POD" -- \
  psql -U postgres -d postgres -P pager=off -x -c "
SELECT
  application_name,
  client_addr,
  state,
  sync_state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)
  ) AS bytes_behind_primary,
  write_lag,
  flush_lag,
  replay_lag
FROM pg_stat_replication
ORDER BY application_name;"
```

You will see the two local J64 replicas plus the cross-site J52 receiver. The J52 row should report:

```text
state = streaming
sync_state = async
```

A small or temporary byte lag is normal. The red flag is lag that continually increases or a missing cross-site row.

### Definitive end-to-end test

This creates a disposable probe table on J64:

```bash
kubectl --context j64seg1opdev -n oppostgres exec "$J64_POD" -- \
  psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "
CREATE TABLE IF NOT EXISTS public.cnpg_replication_probe (
  marker text PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO public.cnpg_replication_probe(marker)
VALUES ('j64-to-j52-' || to_char(clock_timestamp(),'YYYYMMDD-HH24MISS.MS'))
RETURNING *;"
```

Confirm the row appears on J52:

```bash
kubectl --context j52seg1opdev -n oppostgres exec "$J52_POD" -- \
  psql -U postgres -d postgres -P pager=off -c "
SELECT *
FROM public.cnpg_replication_probe
ORDER BY created_at DESC
LIMIT 1;"
```

Then clean it up on J64:

```bash
kubectl --context j64seg1opdev -n oppostgres exec "$J64_POD" -- \
  psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c \
  "DROP TABLE public.cnpg_replication_probe;"
```

If the inserted J64 row becomes readable on J52, the cross-site physical replication path is operational end to end.
