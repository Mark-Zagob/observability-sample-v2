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

**Q2.** 🟡 If you run `docker compose up -d` and the `order-service` container keeps restarting in a loop, how would you diagnose the issue? Walk me through your troubleshooting steps.

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

**Q14.** 🟡 PostgreSQL is running low on connections because all services are connecting to it directly. What are two different approaches to solve this from an **operational** perspective? Which would you recommend for our setup and why?

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

**Q21.** 🟡 A customer reports that their order took 15 seconds to complete. You have Grafana open. Walk me through how you would investigate this — which tools would you use and in what order?

**Q22.** 🟡 What is the difference between a Prometheus **Counter** and a **Histogram**? Give an example of when you'd use each from our application.

**Q23.** 🟡 We propagate trace context from Order Service through Kafka message headers to the workers. Why is this important? What would you lose without it?

**Q24.** 🔴 Our Alertmanager sends alerts to Telegram. An alert fires: `KafkaConsumerLagHigh`. Describe what actions you would take after receiving this alert at 3 AM. How would you decide whether to escalate or handle it yourself?

**Q25.** 🔴 What is the purpose of Prometheus **recording rules**? Why would we pre-compute `job:request_duration_seconds:p95` instead of calculating it on-the-fly in Grafana?

---

## Section 6: CI/CD & Deployment Workflow (4 questions)

**Q26.** 🟢 A developer pushes code to the `main` branch. Describe what a basic CI/CD pipeline should do before deploying the new version to the Docker Compose environment. What are the minimum steps you would include?

**Q27.** 🟡 You are deploying a new version of `order-service`. You run `docker compose pull order-service && docker compose up -d order-service`. What happens to in-flight requests during this process? How would you minimize downtime?

**Q28.** 🟡 After deploying a new version, you discover a critical bug. Describe your rollback plan step by step. How do you ensure the previous version is available? What would you check after rolling back?

**Q29.** 🟡 Your team has 5 developers working on the same codebase. What Git branching strategy would you recommend? How do you decide what goes into a release? Explain how this connects to the deployment pipeline.

---

## Section 7: Troubleshooting Scenarios (5 questions)

**Q30.** 🟡 After deploying a new version, all orders return "unknown error" in the Web UI, but the Order Service logs show orders are being created successfully. Where would you look first? *(Hint: think about the layers between the user and the service)*

**Q31.** 🟡 You run `docker compose up -d` on a fresh VM. PostgreSQL and Redis are healthy, but the Order Service fails to start with `connection refused` to Kafka. The Kafka container is running. What's likely happening?

**Q32.** 🔴 Load testing shows that response times increase dramatically after 5 minutes. CPU and memory look fine. PostgreSQL shows many connections in `idle in transaction` state. What's your hypothesis and how would you verify it?

**Q33.** 🟡 The Events tab in the Web UI shows notifications but no inventory logs. The Inventory Worker `/status` endpoint shows it's running with 0 errors. Where would you investigate?

**Q34.** 🟡 You need to upgrade PostgreSQL from version 16 to 17. Describe your plan step by step, considering that we have data we cannot lose. Focus on the **operational process**, not SQL.

---

## Bonus: Architecture & Mindset (3 questions)

**B1.** 🔴 If you were asked to make this lab "production-ready", name the top 5 changes you would prioritize and explain why. Consider reliability, security, and observability.

**B2.** 🔴 A teammate suggests running Kafka, PostgreSQL, and all application services on a single VM to save costs. What are the risks? How would you justify the current architecture to your manager?

**B3.** 🔴 Looking at our architecture, identify one potential single point of failure and propose a solution. How would you verify that your solution actually works?

---

## Question Distribution

| Level | Count | Percentage |
|-------|-------|------------|
| 🟢 Junior | 9 | 25% |
| 🟡 Mid | 18 | 50% |
| 🔴 Stretch (Senior) | 10 | 25% |
| **Total** | **37** | 100% |

| Section | Questions | Focus |
|---------|-----------|-------|
| Containerization | Q1–Q6 | Docker fundamentals + troubleshooting |
| Networking | Q7–Q10 | DNS, reverse proxy, security |
| Infrastructure Ops | Q11–Q14 | Resource limits, backup, secrets, connections |
| Kafka | Q15–Q19 | Event-driven architecture |
| Observability | Q20–Q25 | Metrics, logs, traces, alerting |
| CI/CD | Q26–Q29 | Pipeline, deployment, rollback, branching |
| Troubleshooting | Q30–Q34 | Cross-cutting diagnosis scenarios |
| Bonus | B1–B3 | Architecture decision-making |

> **Evaluation criteria:**
> - **Technical accuracy** — Is the answer correct?
> - **Depth of understanding** — Do you understand *why*, not just *what*?
> - **Troubleshooting mindset** — Do you approach problems systematically?
> - **Communication** — Can you explain clearly to both technical and non-technical audiences?
