#--------------------------------------------------------------
# Order Service Configuration
#--------------------------------------------------------------
service_name   = "order-service"
image_tag      = "ecs-fargate-v3" # <-- App Team đổi chỗ này khi release code mới
container_port = 5001
cpu            = 256
memory         = 512
