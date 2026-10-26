# 1. Giới thiệu tổng quan

- Folder này bao gồm:
  - `README.md` ở root folder giới thiệu tổng quan dự án
  - `ARCHITECTURE.md` nói về kiến trúc của ứng dụng và `EXPANSION_PLAN.md` dùng để mở rộng ứng dụng sắp tới.  
  - Codebase của một ứng dụng e-commerce với nhiều chức khác nhau.  
  - Codebase của một hệ thống observability dùng để giám sát hạ tầng và ứng dụng đang chạy.  
  - Các tài liệu khác dưới dạng markdown để học, mô phỏng, vận hành hệ thống và ứng dụng.  

---
# 2. Giới thiệu bản thân và role

- Tôi là một **Junior DevOps/SRE/Platform Engineer** .
- Codebase của tất cả services dành cho ứng dụng ecommerce này được vibe code bởi một AI Agents chứ không phải bản thân tôi.  
  > lý do: vì tôi không phải là Developer hay Software Engineer nên không có kiến thức chuyên sâu.
- Thông qua việc triển khai và vận hành ứng dụng này,tôi muốn học, thực hành và trải nghiệm nhiều nhất có thể với các concepts liên quan trực tiếp đến production-grade với team size khác nhau để có thể nâng cao kỹ năng, kiến thức và kinh nghiệm cho bản thân với vai trò là một **DevOps/SRE/Platform Engineer** .

---
# 3. Mục tiêu hướng đến
- Chú trọng cải thiện và nâng cao các kiến thức, khái niệm và kỹ năng của một **DevOps/SRE/Platform Engineer** chứ không phải của một **Software Engineer**.
- **Code Interrogation** (Khi được yêu cầu review code/IaC): Đừng review như một Software Engineer thuần túy. Hãy soi xét dưới góc độ Operability & Reliability. Mọi câu trả lời sẽ hướng về DevOps/SRE/Platform lens, không phải Software Engineer lens.
- Mục tiêu không phải chỉ là làm lab cho biết mà phải làm thật như trong môi trường production để nắm bắt được cái nào là best practices cho production-grade với team size khác nhau.
- Bên cạnh việc triển khai và vận hành ứng dụng, còn có các tài liệu để phục vụ việc mở rộng kiến thức bao gồm:
  - `BREAK_TEST_RECOVERY.md`, `INCIDENT_RUNBOOK.md`, `INCIDENT_SIMULATION_GUIDE.md` , folder `./post-mortems` và các files bên trong để phục vụ cho việc giả lập sự cố, xử lý, báo cáo theo một quy trình chuẩn.
  - `devops-question-senior.md` và `devops-question.md` là files tổng hợp các câu hỏi để kiểm tra kiến thức và vận dụng thông qua bài lab này.
  - `EXPANSION_PLAN.md` là kế hoạch mở rộng ứng dụng này lên với nhiều services hơn để trên vai trò là một DevOps/SRE/Platform Engineer có thể học được thêm nhiều concepts liên quan đến production-grade.

---
# 4. Môi trường triển khai

- Bài lab này được triển khai ở môi trường on-prem sử dụng Docker Compose (giúp deploy nhanh và linh hoạt hơn với k8s cluster), tuy nhiên tất cả các khía cạnh khác vẫn phải hướng đến production-grade chứ không phải chỉ làm lab.
- Việc migrate các ứng dụng đang chạy trên docker compose sang chạy trên on-premises K8S để áp dụng các concepts chuyên sâu về CI/CD và Gitops sẽ được đề xuất sau nên hiện tại hãy only focus vào Docker Compose.
- Ứng dụng này cũng sẽ được triển khai trên môi trường AWS, sử dụng lần lượt ECS và EKS, để có thể tối ưu hóa kiến thức, thực hành và kinh nghiệm trên cloud với tiêu chuẩn production-grade với team size khác nhau.

> **NOTE:** Việc triển khai ứng dụng trên AWS sẽ được thực hiện ở folder `./terraform`, nên folder này chỉ focus hoàn toàn vào môi trường on-prem Docker Compose.