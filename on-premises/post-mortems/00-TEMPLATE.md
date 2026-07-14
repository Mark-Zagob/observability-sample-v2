# Blameless Post-Mortem Template

> **Hướng dẫn sử dụng:**
> 1. Copy file này thành `XX-<Tên-ngắn-gọn>.md` (VD: `02-Kafka-Lag.md`)
> 2. Điền từng section, xóa các dòng prompt `>` khi hoàn thành
> 3. Tham khảo [`01-GOLDEN-EXAMPLE-DB-Saturation.md`](./01-GOLDEN-EXAMPLE-DB-Saturation.md) để xem ví dụ mẫu

---

## 📋 Incident Log (Real-time)

> Ghi lại trong lúc incident đang xảy ra. Đừng tin vào trí nhớ lúc 3 AM!

**Start:** YYYY-MM-DD HH:MM UTC  
**Alert(s):** [tên các alert firing]  
**IC:** [Tên bạn]

### SEV Assessment (ghi trong 30s đầu)
- **Initial SEV:** [1/2/3/4] vì [lý do ngắn gọn - dùng 5 câu impact assessment]
- **Escalation decision:** [Có/Không escalate, ai, tại sao]

### Timeline
- [HH:MM] 🔔 Alert fired: [tên]
- [HH:MM] 👀 Ack alert, bắt đầu investigate
- [HH:MM] 🔍 Check [dashboard] → thấy [observation]
- [HH:MM] 🤔 Hypothesis: [giả thuyết]
- [HH:MM] 🎯 Decision: [action] vì [reason]
  - Considered: [alternative đã cân nhắc]
- [HH:MM] ⚡ Executed: [kết quả]
- [HH:MM] 🔁 **SEV Re-assessment:** [Upgrade/Downgrade/Giữ nguyên] từ SEV-X → SEV-Y vì [lý do]
- [HH:MM] ✅ Alert resolved

### Decisions Log
| Time | Decision | Reason | Alternative considered |
|------|----------|--------|----------------------|
| HH:MM | ... | ... | ... |

### Open Questions
- [ ] ...

---

## 📊 Blameless Post-Mortem

**Date:** YYYY-MM-DD  
**Duration:** X phút  
**SEV:** [1/2/3/4] (Initial: SEV-X, Re-assessed: SEV-Y)  
**Incident Commander:** [Tên]  
**Participants:** [List]

### Executive Summary
> 2-3 câu tóm tắt: gì xảy ra, impact, resolution. Viết sao cho sếp không technical cũng hiểu.

### Impact
- **Users/Requests affected:** [ước lượng]
- **Revenue impact:** [$X hoặc "Không" nếu lab]
- **Error Budget consumed:** [X%]
- **Customer complaints:** [số lượng]

### Timeline (dựa trên Incident Log real-time)
- [HH:MM UTC] — Inject / Trigger event
- [HH:MM UTC] — Alert fired (MTTD = X phút)
- [HH:MM UTC] — Investigating started
- [HH:MM UTC] — Root cause identified
- [HH:MM UTC] — Mitigation applied
- [HH:MM UTC] — Alert resolved (MTTR = X phút)
- [HH:MM UTC] — Monitoring confirmed recovery

### Root Cause Analysis (5 Whys)
> Đào sâu từ triệu chứng → systemic gap. Đừng dừng ở "DB lock" hay "memory leak".

1. **Why** [triệu chứng]? → [answer]
2. **Why** [answer từ #1]? → [answer]
3. **Why** [answer từ #2]? → [answer]
4. **Why** [answer từ #3]? → [answer]
5. **Why** [answer từ #4]? → **[Systemic gap]**

### What Went Well
> Ghi ít nhất 2 điều tích cực. Quan trọng cho morale và learning.

1. [Điều tích cực #1]
2. [Điều tích cực #2]
3. [Điều tích cực #3]

### What Went Poorly
> **KHÔNG blame cá nhân.** Focus vào process/system gaps.

1. [Gap #1]
2. [Gap #2]
3. [Gap #3]

### SEV Assessment Deep Dive
> So sánh Initial SEV vs Re-assessed SEV. Tại sao đúng/sai?

| Câu hỏi Impact Assessment | Trả lời | Impact lên SEV |
|---------------------------|---------|----------------|
| 1. Bao nhiêu % users bị ảnh hưởng? | | |
| 2. Có ảnh hưởng revenue không? | | |
| 3. Có data loss/corruption không? | | |
| 4. Có security implication không? | | |
| 5. Có SLA contractual không? | | |

**So sánh với Context Matrix:** [Xem INCIDENT_SIMULATION_GUIDE.md Part 4]
- Context A (Low Traffic / Off-hours): SEV = ?
- Context B (Peak / Flash Sale): SEV = ?

### Action Items (SMART)
| # | Action | Owner | Deadline | Priority | Status |
|---|--------|-------|----------|----------|--------|
| 1 | [Fix] ... | @... | YYYY-MM-DD | P1 | Open |
| 2 | [Prevent] ... | @... | YYYY-MM-DD | P1 | Open |
| 3 | [Detect] ... | @... | YYYY-MM-DD | P2 | Open |
| 4 | [Process] ... | @... | YYYY-MM-DD | P2 | Open |

### Lessons Learned
> 1-3 bài học chính để chia sẻ với team

1. [Bài học #1]
2. [Bài học #2]
3. [Bài học #3]

### Metrics Summary
| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| **MTTD** (Detect) | X phút | < 5 phút | ✅/❌ |
| **MTTA** (Acknowledge) | X phút | < 5 phút | ✅/❌ |
| **MTTR** (Resolve) | X phút | < 60 phút (SEV-2) | ✅/❌ |
| **Error Budget consumed** | X% | < 5% per incident | ✅/❌ |
| **SEV assessment accuracy** | Match/Mismatch | Match | ✅/❌ |

### Follow-up Schedule
- [ ] **48h:** Review post-mortem, đảm bảo action items rõ ràng
- [ ] **1 week:** Check-in progress P1 action items
- [ ] **1 month:** Verify all action items completed
- [ ] **Quarterly:** Reliability review — xu hướng incidents tương tự

---

## 🔁 Blameless Principles (Nhắc nhở)

- ❌ "Alice deploy code gây crash"
- ✅ "Deploy process không có pre-deployment validation"
- ❌ "Bob không đọc alert sớm"  
- ✅ "Alert routing không đến đúng channel lúc 3 AM"

**Rule:** Mọi "human error" đều là **system gap**. Hệ thống tốt khiến human error khó xảy ra hoặc ít impact.