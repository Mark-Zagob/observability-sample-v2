#--------------------------------------------------------------
# Payment Service Configuration
#--------------------------------------------------------------
service_name = "payment-service"
image_tag    = "ecs-fargate-v3"  # <-- App Team đổi chỗ này khi release code mới
container_port = 5002
cpu          = 256
memory       = 512