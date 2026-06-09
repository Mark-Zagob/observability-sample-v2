# Incident Log — Order Service down
**Start:** 2026-06-09 10:10 UTC+7  
**Alert(s):** ServiceHealthCheckFailed  
**IC:** Dungtt


## Baseline Snapshot — rate:2, duration: 120 - [09:19:25 UTC+7] [2025:06:09]
- Order Service RPS: ~0.351 req/s (từ spanmetrics)
- API Gateway RPS: ~3.7 req/s
- Payment Error rate: ~11.2%
- Duration - Latency (API Gateway): P50 ~ 22 ms, P95 ~ 1.8 ms, P99: 2.35s
- Blackbox probe: SUCCESS (probe_success = 1)
- Prometheus targets: otel=up, blackbox=up
- API Gateway logs: "Order created" mỗi ~500ms
- Order Service logs: "Processing new order" mỗi ~500ms
- Errors — Infrastructure Error Rate : No Data
- Business — Order Success Rate: 88.7%

## Pre-Mortem Hypothesis (GHI TRƯỚC KHI INJECT)
- Alert Lớp 1 (Blackbox) dự kiến nổ tại:  ~ 60s-75s sau khi inject
- Alert Lớp 2 (SpanMetrics) dự kiến nổ tại: ~ 300s sau khi inject 
- API Gateway sẽ phản ứng: fail-fast 502
- Latency API Gateway sẽ: không tăng
- Error Rate API Gateway: TĂNG VỌT lên ~100%
- Kafka produce rate: RỚT về 0 (order-service không publish events)
- Consumer lag: KHÔNG TĂNG (không có event mới để lag)


## SEV Assessment (ghi trong 30s đầu)
- **Initial SEV:** SEV-3 vì trong thời gian thấp điểm, không traffic. (SEV-1 nếu trong thời gian cao điểm, flash sale)
- **Escalation decision:** 
	+ Không escalate trong thời gian thấp điểm (3AM)
	+ CÓ - VP Eng- trong thời gian cao điểm, flash-sale

## Timeline (ghi MỖI khi có action/observation mới)
- [09:19:25] Baseline established, traffic rate=2
- [10:09:50] Baseline established, traffic rate=2
- [10:10:30] 💉 Inject: docker stop order-service
- [10:12:19] 🔔 Alert fired: ServiceHealthCheckFailed
- [10:13:47] 🔔 Alert fired: HighErrorRate - High error rate on api-gateway
- [10:11:20] 🔍 Check Unified Overview
   + API GATEWAY request rate : 13.5 req/s => dự đoán: cao bất thường
   + Order service request rate: 0 req/s => dự đoán: bất thường
   + Payment Error rate: 12.2% => dự đoán: bình thường
- [10:12:40] 🤔 Hypothesis #1: Order service bị vấn đề về connection 
- [10:13:30] 🔍 Check App Performance
   + Api gateway Errors — Error Rate (Infra) : 27.1% => dự đoán tăng bất thường 
   + Order service - Business — Order Success Rate: 66.7% => dự đoán giảm bất thường
- [10:15:30] 🔍 Check Kafka
   + Consumer Group Lag: giảm từ 2 xuống 0 khi đang có traffic => dự đoán bất thường
   + Messages In (per second): giảm về 0 => dự đoán bất thường
- [10:17:00] 🤔 Hypothesis #2: Order service không bắn message và event tới kafka => kiểm tra trạng thái order-service
- [10:17:30] 🎯 Decision: kiểm tra trạng thái của container order-service đang chạy trên application VM
- [10:18:00] Phát hiện: container order-service bị stop
- [10:18:10] ⚡ Executed:
  ```bash
  docker start order-service
  ```