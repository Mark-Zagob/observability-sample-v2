---
incident_id: INC-20260609-001
date: 2026-06-09
severity: SEV-3
status: published # draft | reviewing | published
tags: [experiment-1, order-service, docker, blackbox-exporter]
impact:
  users_affected: ~1140
  revenue_loss: 0
  error_budget_consumed: 0.3%
metrics:
  mttd_minutes: 1.8
  mttr_minutes: 9.5
---
# 📋 BLAMELESS POST-MORTEM

**Incident:** Order Service Down (Service Health Check Failed)  
**Date:** 2026-06-09 | **Duration:** 9 minutes 30 seconds | **SEV:** 3  
**Incident Commander:** Dungtt (Solo Engineer)  
**Participants:** None (solo drill)

---

## 🎯 Executive Summary

> **Viết thế nào:** 2-3 câu ngắn gọn trả lời: WHAT happened, IMPACT gì, RESOLUTION thế nào. Đây là phần stakeholders (VP, PM, Finance) sẽ đọc — họ không cần technical details.

Vào lúc 10:12 UTC+7, Order Service bị stop đột ngột khiến 100% requests tạo đơn hàng thất bại với lỗi 502 Bad Gateway từ API Gateway. Incident kéo dài 9 phút 30 giây, ảnh hưởng đến ~10% traffic bình thường do đang trong khung giờ off-peak (`rate=2` req/s). Service được khôi phục bằng cách restart container, không có data loss. MTTD = 1m 49s, MTTR = 9m 30s, cả hai đều nằm trong SLO targets.

---

## 📊 Impact Assessment

> **Tại sao cần:** Reliability PM cần con số để tính Error Budget consumed và đánh giá business impact. Đây là dữ liệu cho quarterly reliability review.

| Metric | Value | Notes |
|--------|-------|-------|
| **Users affected** | ~100% of checkout users | Toàn bộ users đặt hàng trong 9m30s |
| **Total users online** | ~2 req/s × 570s = ~1,140 requests | Off-peak traffic |
| **Failed requests** | ~1,140 | 100% failure rate trong window |
| **Revenue impact** | None (lab environment) | Production: ước tính ~$XXX dựa trên AOV |
| **Error Budget consumed** | ~0.3% of monthly Availability SLO | 9.5m / 216m monthly budget × 100% error rate |
| **Data loss** | None | Orders chưa tạo, Kafka chưa publish |
| **Customer complaints** | N/A | Lab env |
| **SLA breached** | None | No customer SLA |

---

## ⏱️ Timeline (dựa trên Incident Log real-time)

> **Quy tắc vàng:** Timeline post-mortem PHẢI match 100% với Incident Log. Nếu có discrepancy → Incident Log sai → cần investigate lại.

| Time (UTC+7) | Event | Duration from start |
|--------------|-------|---------------------|
| 09:19:25 | 📊 Baseline collected, system stable | — |
| 10:10:30 | 💉 **Inject:** `docker stop order-service` | 0s (T0) |
| 10:11:20 | 🔍 First dashboard check (Unified Overview) | +50s |
| 10:12:19 | 🔔 **Alert fired:** `ServiceHealthCheckFailed` (Blackbox) | +1m 49s (**MTTD**) |
| 10:12:40 | 🤔 Hypothesis #1: Network issue → REJECT | +2m 10s |
| 10:13:30 | 🔍 Check App Performance → Confirm API Gateway 502 | +3m 00s |
| 10:13:47 | 🔔 **Alert fired:** `HighErrorRate` (api-gateway) | +3m 17s |
| 10:15:30 | 🔍 Check Kafka → Confirm producer dead (lag decreasing) | +5m 00s |
| 10:17:00 | 🤔 Hypothesis #2: Order service container stopped | +6m 30s |
| 10:17:45 | 🎯 **Decision:** Check `docker ps` (considered: logs, OTel) | +7m 15s |
| 10:18:00 | ⚡ **Executed:** `docker ps` → `Exited (0)` | +7m 30s |
| 10:18:10 | ⚡ **Executed:** `docker start order-service` | +7m 40s |
| 10:19:00 | 🔁 Verify recovery (alerts RESOLVED, RPS restored) | +8m 30s |
| 10:20:00 | ✅ **Incident resolved** | +9m 30s (**MTTR**) |

**Metrics Summary:**

- **MTTD** (Detect): 1m 49s — ✅ Within target (< 5 min for SEV-3)
- **MTTA** (Acknowledge): ~0s (solo engineer immediate) — ✅ Within target (< 5 min)
- **MTTR** (Resolve): 9m 30s — ✅ Within target (< 1h for SEV-3)
- **Observation gap**: 50s (inject → first check) — ⚠️ Improvement opportunity

---

## 🔍 Root Cause Analysis — 5 Whys

> **Blameless Principle:** Mỗi "Why" phải dẫn đến system/process gap, KHÔNG phải "human error". Nếu câu trả lời là "tôi quên...", phải hỏi tiếp "Tại sao hệ thống cho phép tôi quên?"

**Why 1:** Tại sao Order Service không xử lý được requests?  
→ Container `order-service` đã stop (Exited status)

**Why 2:** Tại sao container stop?  
→ Lệnh `docker stop order-service` được execute (chaos experiment có chủ đích)

**Why 3:** Tại sao chaos experiment được chạy mà không có safety guardrails?  
→ **Systemic Gap #1:** Không có pre-experiment checklist để verify rollback plan và communicate với stakeholders trước khi inject

**Why 4:** Tại sao phải mất 1m 49s mới detect được service down?  
→ Blackbox Exporter probe interval = 15s + alert `for: 1m` = minimum 75s detection time  
→ **Systemic Gap #2:** Alert rule configuration có inherent delay, không có way để detect nhanh hơn mà không gây false positives

**Why 5:** Tại sao phải mất thêm 7m 30s mới restore service?  
→ On-call engineer phải manually investigate qua 3 dashboards (Unified → App Performance → Kafka) trước khi decide check `docker ps`  
→ **Systemic Gap #3:** Runbook RB-24 có steps đúng nhưng không có automated diagnostic script để gather all relevant info trong 1 command

**Root Cause Summary:**

Incident xảy ra do chaos experiment có chủ đích (expected). Tuy nhiên, MTTR kéo dài 9m30s (thay vì < 2 phút lý tưởng) là do:

1. Thiếu automated diagnostic tooling
2. Phụ thuộc vào manual dashboard navigation
3. Alert rule có inherent delay do design (trade-off để tránh false positives)

---

## ✅ What Went Well

> **Tại sao cần:** Post-mortem không chỉ tìm lỗi. Ghi nhận success giúp team biết what to keep doing. Đây là cultural aspect của Blameless.

1. ✅ **Pre-Mortem Hypothesis chính xác 5/5:**
   - Blackbox alert fired sau 1m49s (expected 60-75s)
   - Kafka produce rate = 0 (expected)
   - Consumer lag KHÔNG tăng (expected, counter-intuitive)
   - API Gateway RPS TĂNG (do Little's Law — fail-fast 502)
   - API Gateway Latency KHÔNG tăng (fail-fast)

2. ✅ **2-layer monitoring working as designed:**
   - Lớp 1 (Blackbox) detect service down trong < 2 phút, KHÔNG cần traffic
   - Lớp 2 (SpanMetrics) KHÔNG fire do rollback sớm — verify được traffic guard hoạt động

3. ✅ **Scientific method applied:**
   - Hypothesize → Check → REJECT/ACCEPT → Refine
   - Không jump to conclusion, follow evidence

4. ✅ **MTTD/MTTR within SLO targets:**
   - MTTD = 1m49s (< 5 min target)
   - MTTR = 9m30s (< 1h target)

5. ✅ **Blast radius contained:**
   - Chỉ Order Service và API Gateway affected
   - Payment, Notification, Inventory workers vẫn hoạt động (graceful degradation)

---

## ⚠️ What Went Poorly (Systemic Gaps)

> **Quy tắc:** KHÔNG blame cá nhân ("tôi quên", "tôi chậm"). Focus vào system/process/tooling gaps.

1. ⚠️ **Timeline lộn xộn trong Incident Log:**
   - Các events không ghi theo chronological order
   - Gây khó khăn khi reconstruct sequence trong post-mortem
   - **Gap:** Không có real-time logging tool (Notion/Obsidian với timestamp shortcut)

2. ⚠️ **Thiếu verify recovery steps:**
   - Sau `docker start`, không verify: container healthy? Alerts RESOLVED? Kafka producer hoạt động lại? Service xử lý được traffic mới?
   - **Gap:** Runbook RB-24 Step 4 (verify) bị skip

3. ⚠️ **50-second observation gap:**
   - Từ lúc inject (10:10:30) đến lúc check dashboard đầu tiên (10:11:20) = 50s
   - Trong production, đây là "blind window" — incident xảy ra nhưng chưa detect
   - **Gap:** Không có automated dashboard auto-open khi alert fires

4. ⚠️ **SEV Assessment thiếu structured reasoning:**
   - Ghi "SEV-3 vì off-hours" nhưng không trả lời đầy đủ 5 câu Impact Assessment
   - **Gap:** Template Incident Log không enforce structured SEV assessment

5. ⚠️ **Alert Lớp 2 chưa verify:**
   - `ServiceNoTraces_OrderService` cần 5 phút để fire
   - Rollback sớm (7m40s) → không verify được alert rule có hoạt động
   - **Gap:** Experiment design không có "wait phase" để verify cả 2 alert layers

---

## 🎯 Action Items (SMART)

> **SMART** = Specific, Measurable, Achievable, Relevant, Time-bound  
> **Quy tắc:** Mỗi action item phải có Owner + Deadline + Priority. Không có owner = không ai làm.

| # | Action | Owner | Deadline | Priority | Status | Category |
|---|--------|-------|----------|----------|--------|----------|
| 1 | **[Tooling]** Tạo bash script `incident-diagnose.sh` tự động gather: `docker ps`, alert status, RPS, Kafka lag, connection pool trong 1 command | @dungtt | 2026-06-16 | P1 | Open | Detect |
| 2 | **[Process]** Update Incident Log template thêm section bắt buộc: "5 Impact Assessment Questions" trước khi ghi SEV | @dungtt | 2026-06-12 | P1 | Open | Prevent |
| 3 | **[Tooling]** Setup Grafana auto-open dashboard khi alert fires (dùng webhook → browser automation) | @dungtt | 2026-06-23 | P2 | Open | Detect |
| 4 | **[Runbook]** Add Step 0 vào RB-24: "Pre-flight checklist" (verify rollback plan, communicate stakeholders) | @dungtt | 2026-06-12 | P1 | Open | Prevent |
| 5 | **[Experiment]** Redesign Experiment 1 để có "wait phase" 5 phút sau inject, verify cả 2 alert layers fire | @dungtt | 2026-06-16 | P2 | Open | Prevent |
| 6 | **[Monitoring]** Add annotation tự động trên Grafana khi inject failure (dùng `annotate.sh` script) | @dungtt | 2026-06-19 | P2 | Open | Detect |

**Priority Definitions:**

- **P1:** Must complete within 1 week, directly reduces MTTR/MTTD
- **P2:** Complete within 2 weeks, improves process/tooling
- **P3:** Nice-to-have, complete within 1 month

---

## 💡 Lessons Learned

> **Viết cho ai:** Team members sẽ đọc để learn. Phải actionable, không chỉ là "we learned X".

1. **2-layer monitoring là defense-in-depth, không phải redundancy:**
   - Blackbox (Lớp 1) detect "service có sống không?" — works 24/7, kể cả 3 AM không traffic
   - SpanMetrics (Lớp 2) detect "service có hoạt động đúng không?" — cần traffic
   - **Production insight:** Nếu chỉ có Lớp 2 → blind spot lúc 3 AM. Nếu chỉ có Lớp 1 → miss performance degradation.

2. **Little's Law giải thích counter-intuitive metrics:**
   - Khi Order Service down, API Gateway RPS TĂNG (3.7 → 13.5 req/s)
   - Lý do: Gateway fail-fast 502 (< 10ms) thay vì chờ 300ms → giải phóng threads nhanh hơn
   - **Production insight:** "RPS tăng" KHÔNG phải lúc nào cũng là good news. Phải correlate với Error Rate.

3. **Kafka consumer lag KHÔNG tăng khi producer chết:**
   - Lag = (Messages produced) - (Messages consumed)
   - Producer chết → không có messages mới → lag giữ nguyên hoặc giảm (consumers catch up backlog cũ)
   - **Production insight:** "Lag = 0" KHÔNG có nghĩa là "pipeline healthy". Phải check produce rate.

4. **Pre-Mortem Hypothesis giảm confirmation bias:**
   - Ghi prediction TRƯỚC KHI inject → buộc bản thân test hypothesis thay vì cherry-pick evidence
   - **Production insight:** Skill này phân biệt Senior vs Junior SRE.

5. **SEV assessment cần business context, không chỉ technical signal:**
   - Cùng alert `critical` (burn-rate) có thể là SEV-1 (flash sale) hoặc SEV-3 (3 AM)
   - **Production insight:** On-call engineer giỏi biết khi nào cần page VP Eng, khi nào chỉ cần tạo ticket.

---

## 📅 Follow-up Schedule

> **Tại sao cần:** Action items không có follow-up = không bao giờ complete. Đây là accountability mechanism.

- [ ] **48h (2026-06-11):** Post-mortem meeting (blameless) — review với mentor/team
- [ ] **1 week (2026-06-16):** Check-in progress Action Items #1, #2, #4, #5
- [ ] **2 weeks (2026-06-23):** Check-in progress Action Items #3, #6
- [ ] **1 month (2026-07-09):** Verify tất cả action items completed, measure MTTR improvement
- [ ] **Quarterly (2026-09-09):** Reliability review — xu hướng incidents, Error Budget trends