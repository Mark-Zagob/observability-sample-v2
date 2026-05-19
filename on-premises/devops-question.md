# DevOps Interview — Junior to Mid-Level
## Based on Observability Lab Tech Stack (On-Premises / Docker Compose)

> **Instructions**: Answer each question in your own words. There are no trick questions — I'm evaluating your understanding, troubleshooting mindset, and ability to explain concepts clearly. Take your time.
>
> **Level guide:**
> - 🟢 **Junior** — foundational knowledge, expected from all candidates
> - 🟡 **Mid** — requires troubleshooting experience and trade-off awareness
> - 🔴 **Stretch** — senior-level depth, bonus points for Junior/Mid candidates

---

## Section 1: Containerization & Docker Compose (6 questions)

**Q1.** 🟢 In our `applications-vm/docker-compose.yml`, we use `depends_on` with `condition: service_healthy`. What is the difference between `service_started` and `service_healthy`? Why does `order-service` depend on PostgreSQL with `service_healthy` but API Gateway depends on `order-service` with only `service_started`?

**Q2.** 🟡 If you run `docker compose up -d` and the `order-service` container keeps restarting in a loop, how would you diagnose the issue? Walk me through your troubleshooting steps. If the service doesn't recover within 10 minutes, who would you notify and what information would you include?

**Q3.** 🟢 We have a `volumes` section defining `postgres_data` and `kafka_data`. What happens to the data inside PostgreSQL if you run `docker compose down`? What about `docker compose down -v`? Why does this distinction matter?

**Q4.** 🟡 Our `init.sql` is mounted to `/docker-entrypoint-initdb.d/init.sql`. You added a new table to `init.sql` and ran `docker compose restart postgres`, but the new table doesn't appear. Why? How would you fix this without losing existing data?

**Q5.** 🟢 All services are connected to the `observability` network with `external: true`. What does `external: true` mean? What would happen if you forgot to create this network before running `docker compose up`?

**Q6.** 🟡 The Kafka container uses a custom healthcheck command: `/opt/kafka/bin/kafka-broker-api-versions.sh`. Why don't we just use a simple TCP port check like `nc -z localhost 9092`? What's the difference between a port being open and a service being truly ready?

---

## Section 2: Networking & Reverse Proxy (4 questions)

**Q7.** 🟢 Our Web UI (nginx) proxies `/api/*` requests to the API Gateway. Why do we use a reverse proxy instead of letting the browser call the API Gateway directly on port 5000?

**Q8.** 🟡 Inside Docker Compose, services communicate using container names (e.g., `http://order-service:5001`). How does Docker DNS resolution work? If you renamed a service in `docker-compose.yml`, what else would you need to update?

**Q9.** 🟡 A user reports that the Web UI loads fine but all API calls return "502 Bad Gateway". The API Gateway container is running. What are the most likely causes and how would you investigate?

**Q10.** 🟡 We expose different services on different host ports (5000, 5001, 5002...). In a production environment, would you expose all these ports? What would you do differently and why?

---

## Section 3: Infrastructure Operations (4 questions)

**Q11.** 🟡 The Redis container is killed by the kernel with an OOM (Out of Memory) error. How would you find evidence of this? How do you set memory limits for a container in Docker Compose, and what is the difference between `mem_limit` and `mem_reservation`?

**Q12.** 🟡 You need to back up the PostgreSQL database before a major deployment. Compare two approaches: running `pg_dump` inside the container vs. copying the Docker volume directly. When would you use each? What are the risks of each approach?

**Q13.** 🟡 Our `docker-compose.yml` has database credentials hardcoded as environment variables (e.g., `POSTGRES_PASSWORD=postgres`). What are the security risks? Describe at least two better approaches to manage secrets in a Docker Compose environment.

**Q14.** 🔴 PostgreSQL is running low on connections because all services are connecting to it directly. What are two different approaches to solve this from an **operational** perspective? Which would you recommend and why? Now consider: your team has only 2 engineers and no DBA — does your recommendation change?

---

## Section 4: Kafka & Event-Driven Architecture (5 questions)

**Q15.** 🟢 Explain the difference between Kafka and a traditional message queue like RabbitMQ. Why would an architecture use Kafka instead of direct HTTP calls between services?

**Q16.** 🟡 Our Kafka is configured with `KAFKA_NUM_PARTITIONS: 3` and `KAFKA_AUTO_CREATE_TOPICS_ENABLE: true`. If we scale the Notification Worker to 5 instances (same consumer group), how many instances will actually process messages? Why?

**Q17.** 🟢 A developer asks: *"Why don't we just call the Notification Worker via HTTP from the Order Service instead of using Kafka?"* How would you explain the benefits of the event-driven approach?

**Q18.** 🔴 You notice that the `order.events` topic has a growing consumer lag for the `inventory-workers` group. What does consumer lag mean? How would you diagnose and fix it?

**Q19.** 🔴 We use KRaft mode instead of ZooKeeper for Kafka. What is the main advantage? In a production environment with 3 brokers, how would the KRaft configuration differ from our single-broker setup?

---

## Section 5: Observability — Metrics, Logs & Traces (6 questions)

**Q20.** 🟢 Explain the "three pillars of observability" and give a specific example from our lab for each pillar.

**Q21.** 🟡 A customer reports that their order took 15 seconds to complete. You have Grafana open. Walk me through the investigation using the 5-step Incident Flow: (1) Alerting Overview, (2) Unified Overview, (3) App Performance / SLO / Infrastructure, (4) Tracing, (5) DB/Cache/Kafka. At each step, what specific metric would you check, and what tells you to move to the next step?

**Q22.** 🟡 What is the difference between a Prometheus **Counter** and a **Histogram**? Give an example of when you'd use each from our application.

**Q23.** 🟡 We propagate trace context from Order Service through Kafka message headers to the workers. Why is this important? What would you lose without it?

**Q24.** 🔴 Our Alertmanager sends alerts to Telegram. An alert fires: `KafkaConsumerLagHigh`. Describe what actions you would take after receiving this alert at 3 AM. How would you decide whether to escalate or handle it yourself?

**Q25.** 🔴 What is the purpose of Prometheus **recording rules**? Why would we pre-compute `job:request_duration_seconds:p95` instead of calculating it on-the-fly in Grafana?

**Q26.** 🟢 What is the difference between `docker compose logs order-service` and `docker logs order-service`? When would you use flags like `-f`, `--since`, and `--tail`? Why is it important to know these when troubleshooting a production issue?

**Q27.** 🟡 Our services use structured JSON logging (e.g., `{"timestamp": "...", "level": "INFO", "message": "...", "trace_id": "..."}`) instead of plain text logs. What are the advantages of structured logging? How does including `trace_id` in every log line help during incident investigation?

**Q28.** 🟡 Our SLO target is 99.5% availability for the API Gateway. (a) Calculate how many minutes of downtime are allowed per month (30 days). (b) What is an "error budget" and what should happen when it runs out? (c) What does "burn rate" mean at a high level — why is alerting on burn rate better than alerting on raw error rate? (d) Why is this concept important for balancing reliability and feature velocity?

**Q29.** 🟢 Our lab uses a Blackbox Exporter that sends HTTP requests to each service's `/health/live` endpoint every 15 seconds. (a) How is this different from Prometheus scraping application metrics from the OTel Collector? (b) If there is zero user traffic at 3 AM, which monitoring method can still detect a service crash — and why? (c) What is the term for this type of monitoring? (active probing vs passive monitoring)

**Q30.** 🟡 You're investigating an alert at 2 AM. Grafana shows the incident happened between 00:00–02:00. But when you check `docker logs --timestamps`, the relevant events show timestamps around 17:00–19:00 UTC — hours earlier than expected. (a) What could cause this discrepancy? (b) How do you determine which timeline is correct? (c) What should be the team standard for timezone in monitoring tools?

**Q31.** 🟡 After a load test ends, you notice an SLO burn rate alert is still firing even though all services are healthy and no traffic is flowing. The error rate on the dashboard appears "frozen" at the last value. (a) Why doesn't the error rate drop to 0 when traffic stops? (b) What should the on-call engineer do — wait, silence the alert, or generate new traffic? (c) What condition could be added to the alert rule to prevent this "phantom alert"?

**Q32.** 🟡 A Kafka consumer lag alert fires. You check the lag: 150 messages and growing. Meanwhile, the API Gateway error rate is still 0% and customers haven't reported any issues yet. (a) Why can consumer lag increase before any user-facing errors appear? (b) What kind of indicator is consumer lag — leading or lagging? (c) Give another example of a leading indicator from our monitoring setup.

---

## Section 6: CI/CD & Deployment Workflow (4 questions)

**Q33.** 🟢 A developer pushes code to the `main` branch. Describe what a basic CI/CD pipeline should do before deploying the new version to the Docker Compose environment. What are the minimum steps you would include?

**Q34.** 🟡 You are deploying a new version of `order-service`. You run `docker compose pull order-service && docker compose up -d order-service`. What happens to in-flight requests during this process? How would you minimize downtime? Consider: does your approach change if your team deploys once a week vs. ten times a day?

**Q35.** 🟡 After deploying a new version, you discover a critical bug. Describe your rollback plan step by step. How do you ensure the previous version is available? What would you check after rolling back?

**Q36.** 🟢 Your team has 5 developers working on the same codebase. What Git branching strategy would you recommend? How do you decide what goes into a release? Explain how this connects to the deployment pipeline.

---

## Section 7: Troubleshooting Scenarios (6 questions)

**Q37.** 🟡 After deploying a new version, all orders return "unknown error" in the Web UI, but the Order Service logs show orders are being created successfully. Where would you look first? *(Hint: think about the layers between the user and the service)*

**Q38.** 🟡 You run `docker compose up -d` on a fresh VM. PostgreSQL and Redis are healthy, but the Order Service fails to start with `connection refused` to Kafka. The Kafka container is running. What's likely happening?

**Q39.** 🔴 Load testing shows that response times increase dramatically after 5 minutes. CPU and memory look fine. PostgreSQL shows many connections in `idle in transaction` state. What's your hypothesis and how would you verify it?

**Q40.** 🟡 The Events tab in the Web UI shows notifications but no inventory logs. The Inventory Worker `/status` endpoint shows it's running with 0 errors. Where would you investigate? If you're the only person on-call, how do you prioritize this vs. other active alerts?

**Q41.** 🟡 You need to upgrade PostgreSQL from version 16 to 17. Describe your plan step by step, considering that we have data we cannot lose. Focus on the **operational process**, not SQL. How would your plan differ if you're a solo engineer vs. part of a team with a DBA?

**Q42.** 🟡 The SLO Overview dashboard shows API Gateway availability at 98.2% — below the 99.5% target. But the App Performance dashboard shows all services have 0% error rate right now. No alerts other than the SLO burn rate are firing, and the Unified Overview shows 0 RPS across all services. (a) Is this a real incident or a false alarm? How do you determine this? (b) What does "stale metrics" mean in this context? (c) Which dashboard gives you the most useful signal when there is zero traffic?

---

## Bonus: Architecture & Mindset (3 questions)

**B1.** 🔴 If you were asked to make this lab "production-ready", name the top 5 changes you would prioritize and explain why. Consider reliability, security, and observability.

**B2.** 🔴 A teammate suggests running Kafka, PostgreSQL, and all application services on a single VM to save costs. What are the risks? How would you justify the current architecture to your manager?

**B3.** 🔴 Looking at our architecture, identify one potential single point of failure and propose a solution. How would you verify that your solution actually works?

---

## Question Distribution

| Level | Count | Percentage |
|-------|-------|------------|
| 🟢 Junior | 12 | 27% |
| 🟡 Mid | 23 | 51% |
| 🔴 Stretch (Senior) | 10 | 22% |
| **Total** | **45** | 100% |

| Section | Questions | Focus |
|---------|-----------|-------|
| Containerization | Q1–Q6 | Docker fundamentals + troubleshooting |
| Networking | Q7–Q10 | DNS, reverse proxy, security |
| Infrastructure Ops | Q11–Q14 | Resource limits, backup, secrets, connections |
| Kafka | Q15–Q19 | Event-driven architecture |
| Observability | Q20–Q32 | Metrics, logs, traces, alerting, SLO, active probing, timezone, phantom alerts |
| CI/CD | Q33–Q36 | Pipeline, deployment, rollback, branching |
| Troubleshooting | Q37–Q42 | Cross-cutting diagnosis, stale metrics scenarios |
| Bonus | B1–B3 | Architecture decision-making |

> **Evaluation criteria:**
> - **Technical accuracy** — Is the answer correct?
> - **Depth of understanding** — Do you understand *why*, not just *what*?
> - **Troubleshooting mindset** — Do you approach problems systematically?
> - **Communication** — Can you explain clearly to both technical and non-technical audiences?
> - **Team awareness** — Do you consider team size and constraints in your answers?


