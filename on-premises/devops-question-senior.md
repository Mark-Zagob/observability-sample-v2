# DevOps Interview — Senior Level
## Based on Observability Lab Tech Stack (On-Premises / Docker Compose)

> **Target:** Senior DevOps / SRE / Platform Engineer (5+ years experience)
>
> **What differentiates Senior from Mid:**
> - Mid explains "what" and "how" → Senior explains "why" and "trade-offs"
> - Mid follows runbooks → Senior designs runbooks and identifies gaps
> - Mid monitors systems → Senior designs monitoring strategy and SLOs
> - Mid deploys services → Senior designs deployment architecture and blast radius controls
>
> **Evaluation criteria:**
> - **System thinking** — Can you see the big picture and identify cascading effects?
> - **Trade-off articulation** — Can you explain why you chose A over B?
> - **Production scars** — Do your answers reflect real-world experience?
> - **Teaching ability** — Can you explain complex concepts to junior engineers?

---

## Section 1: Architecture & Design Decisions (5 questions)

**S1.** Our architecture separates Applications VM and Observability VM. A junior engineer asks: "Why not put everything on one VM?" Beyond the obvious resource answer, explain the architectural reasons. What failure modes does this separation protect against? What new failure modes does it introduce?

**S2.** The Order Service communicates with Payment Service via synchronous HTTP, but with Notification Worker and Inventory Worker via asynchronous Kafka events. Explain the design rationale. Under what circumstances would you change Payment to async? What would be the implications?

**S3.** Looking at the current architecture, we have a single PostgreSQL instance shared by Order Service, Notification Worker, and Inventory Worker. Design a migration plan to split this into separate databases per service. Cover: data ownership, migration strategy, cross-service queries, and what breaks during migration.

**S4.** Our Inventory Worker recently had a deadlock: stock reached 0, but no `stock.depleted` event was published, so auto-restock never triggered. This is a design-level failure, not a code bug. How would you redesign the stock management to be self-healing? Consider at least two approaches and compare their trade-offs.

**S5.** The Web UI uses nginx as a reverse proxy. When a backend container is rebuilt, nginx caches the old IP and returns 502. How would you solve this at the infrastructure level (not "restart nginx")? Discuss at least two approaches: DNS-based, sidecar-based, or service mesh.

---

## Section 2: Observability Strategy (5 questions)

**S6.** Explain the RED method and USE method. For each service in our lab (API Gateway, Order Service, Payment Service, Notification Worker, Inventory Worker, PostgreSQL, Redis, Kafka), decide which method applies and why. Are there any services where both methods apply?

**S7.** Our SLO is set at 99.5% availability for the API Gateway. Calculate: (a) the monthly error budget in minutes, (b) if we're burning at 2x rate, how long until the budget is exhausted, (c) what organizational decisions should be triggered when the budget hits 50%? Design a burn rate alerting strategy with fast-burn and slow-burn windows. (d) What happens to burn rate calculations during zero-traffic periods (e.g., 2-6 AM for a webhook service receiving ~5 requests/hour)? How would you protect against phantom alerts?

**S8.** A junior engineer adds a new custom metric: `orders_total{status, product_id, customer_id, payment_method, region}`. What's wrong with this from a cardinality perspective? How would you redesign this metric? Explain the concept of cardinality explosion and its impact on Prometheus performance.

**S9.** Our Prometheus scrapes metrics from the OTel Collector, which re-labels all metrics with `job="app-metrics"`. This caused Grafana queries filtering by `job="order-service"` to return no data. Walk through how you would design a labeling strategy that works across the entire pipeline (app → OTel Collector → Prometheus → Grafana). What are the pitfalls of relabeling?

**S10.** Design a structured logging standard for our microservices. Define: (a) mandatory fields for every log line, (b) how to propagate request context (trace_id, span_id, order_id) across service boundaries including through Kafka, (c) log levels policy — when to use INFO vs WARN vs ERROR. Give a bad log example and a good log example.

---

## Section 3: Reliability & Incident Management (5 questions)

**S11.** You receive a PagerDuty alert at 3 AM: `KafkaConsumerLagHigh` for `inventory-workers` group. Walk through your complete incident response: (a) initial triage (what do you check first?), (b) dashboard reading path, (c) mitigation actions, (d) when would you escalate?, (e) post-incident actions.

**S12.** During a load test, response times spike from 50ms to 5 seconds after 10 minutes. CPU and memory look normal. Walk through your systematic debugging approach. How do you differentiate between: database contention, connection pool exhaustion, Kafka backpressure, and application-level thread starvation?

**S13.** Design a chaos experiment for our system. Pick one failure scenario, then write: (a) hypothesis with specific, measurable predictions, (b) steady-state definition with exact metric thresholds, (c) blast radius controls, (d) automated abort criteria, (e) expected dashboard observations at each step of the incident flow. How would you run this safely during business hours? (f) For a 3-person startup with no dedicated SRE, how would you adapt chaos practices to be feasible without a formal game day program?

**S14.** Our Notification Worker uses `at-least-once` delivery semantics. A bug causes it to process the same Kafka message 3 times, sending triplicate notifications. (a) Explain the difference between at-least-once, at-most-once, and exactly-once semantics. (b) How does our current idempotency mechanism (processed_events table) prevent this? (c) What happens if the idempotency check succeeds but the database write fails mid-transaction? (d) Design a more robust solution.

**S15.** Our `init.sql` defines `inventory_log.order_id` as `VARCHAR(8)`. This caused a production incident when the Inventory Worker tried to insert `"auto-restock"` (12 chars) as the order_id. (a) How would you prevent schema-code mismatches systematically? (b) Design a pre-deployment validation process. (c) How would you handle this type of migration in a zero-downtime environment?

---

## Section 4: Infrastructure & Platform Engineering (5 questions)

**S16.** Our Docker Compose setup uses `restart: unless-stopped`. Compare this with Kubernetes restart policies. Design a health check strategy for our services that distinguishes between: (a) process crash (liveness), (b) dependency unavailable (readiness), (c) performance degradation (startup probe equivalent). How would you implement graceful shutdown for a Kafka consumer?

**S17.** Design a secrets management solution for our Docker Compose environment. Requirements: (a) no plaintext passwords in compose files or environment variables, (b) automatic rotation for database credentials, (c) audit trail for secret access, (d) works without external services like Vault (we're on-premises). Compare at least two approaches. (e) Your team has 2 engineers and 2 weeks to improve security. What's the 80/20 solution that delivers the most security value with minimum effort?

**S18.** Our PostgreSQL has no connection pooling. With 5 services connecting directly, we're hitting the default 100 connection limit. (a) Calculate the minimum connections needed given our service configuration (gunicorn workers × services). (b) Design a PgBouncer deployment. (c) What connection pooling mode (session, transaction, statement) would you use for each service and why? (d) How would you monitor pool saturation?

**S19.** Design a backup and disaster recovery strategy for our entire stack. Cover: (a) PostgreSQL (point-in-time recovery vs snapshot), (b) Kafka (topic data + consumer offsets), (c) Grafana dashboards and Prometheus data, (d) RPO and RTO targets for each component, (e) recovery procedure and verification steps. How would you test this strategy regularly?

**S20.** Our observability stack (Prometheus, Grafana, Loki, Tempo) is on a single VM. Design a high-availability architecture for the observability stack itself. Address: (a) What happens when the observability VM goes down? (b) How do you monitor the monitor? (c) Prometheus federation vs Thanos vs Mimir — when to use which? (d) Retention policy design for metrics vs logs vs traces. (e) What's the minimum viable HA for a 5-person team with $500/month extra budget vs. the ideal architecture for a 50-person org?

---

## Section 5: Advanced Troubleshooting Scenarios (5 questions)

**S21.** The team deploys a new version of Order Service. 30 minutes later, the SLO Overview shows error budget burning at 6x. The App Performance dashboard shows error rate is only 2% — seemingly below the SLO threshold. But burn rate is still high. Explain this apparent contradiction. What metric granularity issue could cause this? How would you fix the dashboard to show the real picture?

**S22.** After a Kafka broker restart, the Notification Worker stops processing messages. Logs show: `Group coordinator not available`. The broker is healthy, Kafka UI shows the topic has messages. (a) What is the group coordinator and why is it unavailable after restart? (b) How does consumer group rebalancing work? (c) What configuration parameters affect rebalancing behavior? (d) How would you design the consumer to handle this gracefully?

**S23.** You notice that Tempo is missing traces for approximately 10% of requests, but the OTel Collector shows no dropped spans. (a) Walk through the trace pipeline from application to storage. (b) Where could traces be lost? (c) Our tail-based sampling keeps 100% errors, 100% slow requests, and 10% random. Could the sampling policy itself explain this? (d) How would you verify the sampling is working correctly?

**S24.** Grafana dashboards show that the API Gateway P99 latency is 800ms, but users report pages taking 3-5 seconds. (a) Explain why the dashboard metric doesn't match user experience. (b) What is the difference between server-side latency and end-to-end latency? (c) Design a monitoring approach that captures the true user experience. (d) How would you add client-side observability to our Web UI?

**S25.** A critical production database migration needs to add a NOT NULL column to the `orders` table (10M rows). (a) Explain why `ALTER TABLE ADD COLUMN ... NOT NULL DEFAULT` behavior differs between PostgreSQL versions. (b) Design a zero-downtime migration strategy. (c) How would you monitor the migration's impact on application performance? (d) What's your rollback plan if the migration causes issues?

---

## Section 6: Leadership & Culture (3 questions)

**S26.** You join a team where deployments are manual, there's no monitoring, and developers say "it works on my machine." Design a 90-day plan to introduce DevOps practices. What do you prioritize first? How do you get buy-in from developers who resist change? What metrics would you track to demonstrate improvement?

**S27.** Your team operates this observability lab in production. Design an on-call rotation: (a) escalation policy, (b) runbook structure, (c) alert routing by severity, (d) handoff procedure, (e) post-incident review process. How do you prevent alert fatigue while ensuring critical issues are caught? (f) An engineer reports being woken 3 times last week by phantom alerts — SLO burn rate alerts that fired after traffic stopped due to stale metrics. How would you fix this at the alert rule level, and how would you rebuild the team's trust in the alerting system?

**S28.** A junior engineer on your team made a configuration change that caused a 30-minute outage. How do you handle this from a people management perspective? How do you design systems and processes to make such human errors less impactful? Reference the concept of blameless post-mortems.

---

## Section 7: Production Edge Cases (3 questions)

**S29.** You're reviewing our lab's SLO burn rate alert rules and notice that the Latency alerts include `sum(rate(http_requests_total[5m])) > 0.1` as a "traffic guard" but the Availability alerts originally did not. (a) What problem does this traffic guard condition prevent? (b) The recording rules use `or vector(1)` as a fallback when `rate()` returns NaN — why isn't this fallback sufficient to prevent false alerts? (c) Design a traffic guard strategy for all 6 SLO alerts (3 fast-burn, 3 slow-burn). What threshold would you choose and why? (d) What are the trade-offs of setting the threshold too high vs. too low?

**S30.** You receive `APIGatewayFastBurn` at 02:00 local time (UTC+7). Grafana (set to browser timezone) shows the time window 00:00–02:00 with availability at 92%. You check `docker logs --timestamps` and find the last traffic-gen run was at 14:40 UTC+7 (07:40 UTC) — 9 hours before the dashboard window. (a) Explain the timezone mismatch and how it affects your investigation timeline. (b) What evidence would you use to determine if this is a real incident or stale metrics from the earlier traffic run? (c) Design a timezone standard for a distributed team spanning Vietnam, US-West, and EU — covering dashboards, logs, incident communication, and handoff procedures.

**S31.** Our monitoring has four layers: (1) Blackbox Exporter probing `/health/live`, (2) Prometheus scraping application metrics via OTel Collector, (3) Distributed tracing via Tempo, (4) SLO burn rate alerts from recording rules. Design a failure matrix: for each layer, (a) what failure types can it detect, (b) what failure types does it miss, (c) what happens when the monitoring layer itself fails. Then answer: if you could only keep 2 of these 4 layers due to budget constraints, which 2 would you keep and why?

---

## Question Distribution

| Section | Questions | Focus |
|---------|-----------|-------|
| Architecture & Design | S1–S5 | System design, trade-offs, migration planning |
| Observability Strategy | S6–S10 | Monitoring design, SLO math, cardinality, labeling |
| Reliability & Incidents | S11–S15 | Incident response, chaos engineering, data consistency |
| Infrastructure & Platform | S16–S20 | HA design, secrets, connection pooling, DR strategy |
| Advanced Troubleshooting | S21–S25 | Non-obvious diagnosis, pipeline debugging, migration |
| Leadership & Culture | S26–S28 | Team building, on-call design, blameless culture |
| Production Edge Cases | S29–S31 | Traffic guards, timezone traps, monitoring layer design |

> **Scoring guidance:**
> - **Strong hire:** Can articulate trade-offs across team sizes, references real production incidents, considers failure modes and edge cases, teaches clearly
> - **Hire:** Solid technical depth, good troubleshooting process, identifies most issues, aware of team-size implications
> - **Borderline:** Knows solutions but can't explain trade-offs, lacks production depth, answers don't change with constraints
> - **No hire:** Theoretical answers only, can't walk through systematic debugging, no awareness of blast radius or operational maturity
