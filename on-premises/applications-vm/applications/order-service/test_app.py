"""
============================================================
Unit Tests — Order Service
============================================================
Test core business logic mà KHÔNG cần PostgreSQL, Redis, Kafka.
Mock toàn bộ external dependencies.

Chạy: pytest test_app.py -v
============================================================
"""

import pytest
from unittest.mock import patch, MagicMock
from app import app

# ============================================================
# Fixture: Flask test client (mock all external deps)
# ============================================================
@pytest.fixture
def client():
    """Mock OTel + DB + Redis + Kafka trước khi import app"""
    with patch("opentelemetry.sdk.trace.export.BatchSpanProcessor"), \
         patch("opentelemetry.exporter.otlp.proto.grpc.trace_exporter.OTLPSpanExporter"), \
         patch("opentelemetry.exporter.otlp.proto.grpc.metric_exporter.OTLPMetricExporter"), \
         patch("opentelemetry.sdk.metrics.export.PeriodicExportingMetricReader"), \
         patch("opentelemetry.instrumentation.psycopg2.Psycopg2Instrumentor"), \
         patch("opentelemetry.instrumentation.redis.RedisInstrumentor"):

        import importlib
        import app as app_module
        importlib.reload(app_module)

        app_module.app.config['TESTING'] = True
        with app_module.app.test_client() as test_client:
            yield test_client, app_module


# ============================================================
# Test parse_db_url utility function (now in shared)
# ============================================================
class TestParseDbUrl:
    """Test URL parser — pure function, no mocking needed"""

    def test_parse_standard_url(self):
        from shared.db_utils import parse_db_url
        # secretlint-disable-next-line
        result = parse_db_url("postgresql://user:pass@host:5432/mydb")
        assert result['user'] == 'user'
        assert result['password'] == 'pass'
        assert result['host'] == 'host'
        assert result['port'] == 5432
        assert result['dbname'] == 'mydb'

    def test_parse_production_url(self):
        from shared.db_utils import parse_db_url
        # secretlint-disable-next-line
        result = parse_db_url("postgresql://admin:s3cret@db.prod:5433/orders_prod")
        assert result['user'] == 'admin'
        assert result['port'] == 5433
        assert result['dbname'] == 'orders_prod'

    def test_parse_url_with_sslmode_query(self):
        """AWS RDS URL có ?sslmode=require — dbname KHÔNG được nuốt query string.

        Regression: trước đây parse_db_url trả dbname='orders?sslmode=require'
        → PostgreSQL báo 'database "orders?sslmode=require" does not exist'.
        """
        from shared.db_utils import parse_db_url
        # secretlint-disable-next-line
        result = parse_db_url("postgresql://app:pw@db.rds.amazonaws.com:5432/orders?sslmode=require")
        assert result['dbname'] == 'orders'
        assert result['sslmode'] == 'require'
        assert result['port'] == 5432


# ============================================================
# Test /health endpoints
# ============================================================
class TestHealthEndpoints:

    @patch.object(MagicMock, 'check_health', return_value=True)
    def test_health_live_returns_200(self, _, client):
        """Liveness check — process is running"""
        test_client, _ = client
        resp = test_client.get('/health/live')
        assert resp.status_code == 200
        data = resp.get_json()
        assert data['status'] == 'up'
        assert data['service'] == 'order-service'

    @patch('app.cache')
    @patch('app.db')
    def test_health_ready_all_connected(self, mock_db, mock_cache, client):
        """Readiness check khi DB + Redis đều OK"""
        test_client, _ = client
        mock_db.check_health.return_value = True
        mock_cache.check_health.return_value = True

        resp = test_client.get('/health/ready')
        assert resp.status_code == 200
        data = resp.get_json()
        assert data['status'] == 'ready'

    @patch('app.cache')
    @patch('app.db')
    def test_health_ready_db_down(self, mock_db, mock_cache, client):
        """Readiness not_ready khi DB fail"""
        test_client, _ = client
        mock_db.check_health.side_effect = Exception("Connection refused")
        mock_cache.check_health.return_value = True

        resp = test_client.get('/health/ready')
        assert resp.status_code == 503
        data = resp.get_json()
        assert data['status'] == 'not_ready'


# ============================================================
# Test /products endpoint
# ============================================================
class TestProductsEndpoint:

    @patch('app.cache')
    @patch('app.db')
    def test_products_from_cache(self, mock_db, mock_cache, client):
        """Cache hit → trả về từ cache, không query DB"""
        test_client, _ = client
        mock_cache.get.return_value = [
            {'id': 1, 'name': 'Laptop', 'price': 999.99, 'stock': 50}
        ]

        resp = test_client.get('/products')
        assert resp.status_code == 200
        data = resp.get_json()
        assert data['source'] == 'cache'
        mock_db.execute.assert_not_called()

    @patch('app.cache')
    @patch('app.db')
    def test_products_cache_miss_query_db(self, mock_db, mock_cache, client):
        """Cache miss → query DB → set cache"""
        test_client, _ = client
        mock_cache.get.return_value = None
        mock_db.execute.return_value = [
            {'id': 1, 'name': 'Laptop', 'price': 999.99, 'stock': 50, 'category': 'Electronics'}
        ]

        resp = test_client.get('/products')
        assert resp.status_code == 200
        data = resp.get_json()
        assert data['source'] == 'database'
        mock_db.execute.assert_called_once()
        mock_cache.set.assert_called_once()


# ============================================================
# Test /process endpoint (create order)
# ============================================================
class TestProcessOrder:

    @patch('app.publish_event')
    @patch('app.get_kafka_producer')
    @patch('app.requests.post')
    @patch('app.cache')
    @patch('app.db')
    def test_create_order_success(self, mock_db, mock_cache, mock_payment,
                                   mock_kafka, mock_publish, client):
        """Happy path: product exists → payment OK → order created"""
        test_client, _ = client

        mock_cache.get.return_value = None
        mock_cache.delete.return_value = None

        # DB returns: 1) product info, 2) stock check, 3) insert, 4) update stock, 5) update order
        mock_db.execute.side_effect = [
            [{'id': 1, 'name': 'Laptop', 'price': 999.99, 'stock': 50}],  # get product
            [{'stock': 50}],    # check inventory
            1,                  # insert order
            1,                  # update stock
            1,                  # update order with payment
        ]

        mock_payment.return_value = MagicMock(
            status_code=200,
            json=lambda: {'status': 'charged', 'transaction_id': 'TXN-001'}
        )

        mock_kafka_instance = MagicMock()
        mock_kafka.return_value = mock_kafka_instance

        resp = test_client.post('/process',
                                json={'product_id': 1, 'quantity': 2},
                                content_type='application/json')
        assert resp.status_code == 200
        data = resp.get_json()
        assert data['status'] == 'completed'
        assert data['product'] == 'Laptop'
        assert data['quantity'] == 2

    @patch('app.publish_event')
    @patch('app.get_kafka_producer')
    @patch('app.cache')
    @patch('app.db')
    def test_create_order_product_not_found(self, mock_db, mock_cache,
                                             mock_kafka, mock_publish, client):
        """Product không tồn tại → RFC 7807 404"""
        test_client, _ = client

        mock_cache.get.return_value = None
        mock_db.execute.return_value = []  # Product not found

        resp = test_client.post('/process',
                                json={'product_id': 999, 'quantity': 1},
                                content_type='application/json')
        assert resp.status_code == 404
        data = resp.get_json()
        assert data['title'] == 'Product Not Found'
        assert data['status'] == 404

    @patch('app.publish_event')
    @patch('app.get_kafka_producer')
    @patch('app.cache')
    @patch('app.db')
    def test_create_order_out_of_stock(self, mock_db, mock_cache,
                                       mock_kafka, mock_publish, client):
        """Stock không đủ → RFC 7807 409"""
        test_client, _ = client

        mock_cache.get.return_value = None
        mock_db.execute.side_effect = [
            [{'id': 1, 'name': 'Laptop', 'price': 999.99, 'stock': 1}],  # product
            [{'stock': 1}],  # stock check: chỉ có 1, cần 5
        ]

        resp = test_client.post('/process',
                                json={'product_id': 1, 'quantity': 5},
                                content_type='application/json')
        assert resp.status_code == 409
        data = resp.get_json()
        assert data['title'] == 'Out of Stock'
        assert data['status'] == 409
        assert 'trace_id' in data  # RFC 7807 includes trace_id for correlation

@pytest.fixture
def plain_client():
    """Flask test client KHÔNG mock OTel/DB/Redis/Kafka — dùng riêng cho
    2 SRE contract test bên dưới (chúng tự patch app.requests.post,
    app.db.execute, app.cache.get trực tiếp qua module `app` gốc).

    LƯU Ý: KHÔNG được đặt tên trùng `client` với fixture ở đầu file —
    Python module chỉ giữ định nghĩa cuối cùng cho cùng 1 tên, nên nếu
    trùng tên, fixture `client` (có mock OTel/DB/Redis/Kafka, yield tuple
    (test_client, app_module)) ở đầu file sẽ bị ghi đè hoàn toàn, khiến
    mọi test dùng `client` ở các class phía trên nhận nhầm object này
    (yield trực tiếp, không phải tuple) và crash với TypeError khi
    unpack "test_client, _ = client".
    """
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

# ============================================================================
# SRE CONTRACT TESTS: Preventing the HTTP 200 Trap
# ============================================================================

@patch('app.requests.post')
@patch('app.db.execute')
@patch('app.cache.get')
def test_payment_timeout_must_return_502_bad_gateway(mock_cache_get, mock_db_execute, mock_requests_post, plain_client):
    """
    [Infra Failure] Khi Payment Service timeout (infra failure), 
    Order Service PHẢI trả về 502 Bad Gateway, TUYỆT ĐỐI KHÔNG ĐƯỢC là 200 OK.
    """
    # Setup Mocks: Cache hit để bypass DB query sản phẩm
    mock_cache_get.return_value = [{"id": 1, "name": "Test Product", "price": 10.0, "stock": 100}]
    mock_db_execute.return_value = [{"stock": 100}] 
    
    # Simulate Payment Service Timeout (Infrastructure Failure)
    mock_requests_post.side_effect = Exception("Connection timeout")

    # Execute
    response = plain_client.post('/process', json={"product_id": 1, "quantity": 1})

    # Assert HTTP Semantic
    assert response.status_code == 502, \
        "🚨 HTTP 200 Trap detected! Payment timeout must return 502 Bad Gateway for SRE SLI accuracy."
    
    # Assert Payload (Backward compatibility for Web UI)
    data = response.get_json()
    assert data['status'] == 'payment_error'


@patch('app.requests.post')
@patch('app.db.execute')
@patch('app.cache.get')
def test_payment_rejected_must_return_402_payment_required(mock_cache_get, mock_db_execute, mock_requests_post, plain_client):
    """
    [Business Failure] Khi Payment Gateway từ chối giao dịch (business failure), 
    Order Service PHẢI trả về 402 Payment Required.
    """
    mock_cache_get.return_value = [{"id": 1, "name": "Test Product", "price": 10.0, "stock": 100}]
    mock_db_execute.return_value = [{"stock": 100}]
    
    # Simulate Payment Gateway rejection (e.g., Stripe returns 400 Bad Request)
    mock_response = MagicMock()
    mock_response.status_code = 400 
    mock_response.json.return_value = {"status": "failed", "error": "insufficient_funds"}
    mock_requests_post.return_value = mock_response

    response = plain_client.post('/process', json={"product_id": 1, "quantity": 1})

    assert response.status_code == 402, \
        "🚨 Business failure must return 4xx (402 Payment Required), not 5xx or 200."
    
    data = response.get_json()
    assert data['status'] == 'payment_failed'