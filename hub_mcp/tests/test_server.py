import pytest
import sys
import os
from unittest.mock import AsyncMock, patch

# Ajouter le parent (HUBapp_TEMPLATE/) au path pour que hub_mcp.tools importe backend.*
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from mcp.server import Server
from mcp.types import ListToolsRequest, CallToolRequest, CallToolRequestParams


class TestMCPHubTools:
    """Tests du serveur MCP Hub Tools."""

    @pytest.fixture
    def server(self):
        from mcp.server import Server
        return Server("hub-tools-test")

    def test_server_name(self, server):
        assert server.name == "hub-tools-test"

    @pytest.mark.asyncio
    async def test_list_tools_returns_tools(self, server):
        """Le handler list_tools doit retourner une liste non vide."""
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)
        result = await server.request_handlers[ListToolsRequest](None)
        tools = result.root.tools
        assert len(tools) > 0
        tool_names = [t.name for t in tools]
        assert "hub_health" in tool_names
        assert "hub_raw_call" in tool_names

    @pytest.mark.asyncio
    async def test_call_tool_health(self, server):
        """Le tool hub_health doit appeler l'API health du Hub."""
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"status": "ok"}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_health", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/health", method="GET")
            assert result.root.content[0].type == "text"
            assert "ok" in result.root.content[0].text

    @pytest.mark.asyncio
    async def test_hub_health(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"status": "ok", "version": "2.2.0"}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_health", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/health", method="GET")
            assert "status" in result.root.content[0].text

    @pytest.mark.asyncio
    async def test_hub_config(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"debug": False}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_config", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/config", method="GET")
            assert "debug" in result.root.content[0].text

    @pytest.mark.asyncio
    async def test_hub_system_time(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"utc": "2025-01-01T00:00:00Z"}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_system_time", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/system/time", method="GET")

    @pytest.mark.asyncio
    async def test_hub_app_list(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"apps": [{"slug": "test-app", "name": "Test"}]}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_app_list", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/apps/", method="GET")
            assert "test-app" in result.root.content[0].text

    @pytest.mark.asyncio
    async def test_hub_app_get(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"slug": "myapp", "name": "My App"}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_app_get", arguments={"app_id": 1}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/apps/1", method="GET")
            assert "My App" in result.root.content[0].text

    @pytest.mark.asyncio
    async def test_hub_app_register(self, server):
        from hub_mcp.tools import register_all_tools, hub_client
        register_all_tools(server)

        with patch.object(hub_client, "register", new_callable=AsyncMock) as mock_reg:
            mock_reg.return_value = True
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_app_register", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_reg.assert_called_once()
            assert "enregistree" in result.root.content[0].text.lower()

    @pytest.mark.asyncio
    async def test_hub_app_get_credentials(self, server):
        from hub_mcp.tools import register_all_tools, hub_client
        register_all_tools(server)

        from unittest.mock import MagicMock
        creds = MagicMock()
        creds.client_id = "test-client-id"
        creds.client_secret = "test-secret"
        creds.access_token = None
        hub_client._credentials = creds
        try:
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_app_get_credentials", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            assert "test-client-id" in result.root.content[0].text
        finally:
            hub_client._credentials = None

    @pytest.mark.asyncio
    async def test_hub_app_docker_scan(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"containers": []}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_app_docker_scan", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/apps/docker/scan", method="GET")

    @pytest.mark.asyncio
    async def test_hub_user_list(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"users": [{"username": "admin"}]}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_user_list", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/users/", method="GET")
            assert "admin" in result.root.content[0].text

    @pytest.mark.asyncio
    async def test_hub_user_create(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"id": 1, "username": "newuser"}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(
                    name="hub_user_create",
                    arguments={"username": "newuser", "password": "s3cret", "email": "new@test.com"},
                ),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with(
                "/api/users/", method="POST",
                json={"username": "newuser", "password": "s3cret", "email": "new@test.com"}
            )

    @pytest.mark.asyncio
    async def test_hub_user_delete(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"deleted": True}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_user_delete", arguments={"user_id": 5}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/users/5", method="DELETE")

    @pytest.mark.asyncio
    async def test_hub_auth_login(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"access_token": "jwt..."}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(
                    name="hub_auth_login",
                    arguments={"username": "admin", "password": "pass"}
                ),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with(
                "/api/auth/token", method="POST",
                data={"grant_type": "password", "username": "admin", "password": "pass"}
            )

    @pytest.mark.asyncio
    async def test_hub_auth_get_jwks(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.fetch_jwks", new_callable=AsyncMock) as mock_fetch:
            mock_fetch.return_value = {"keys": [{"kty": "RSA"}]}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_auth_get_jwks", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_fetch.assert_called_once()

    @pytest.mark.asyncio
    async def test_hub_auth_create_bootstrap_token(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"token": "bt-xxx", "id": 1}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(
                    name="hub_auth_create_bootstrap_token",
                    arguments={"app_slug": "myapp", "scope": "register"}
                ),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with(
                "/api/apps/bootstrap-tokens", method="POST",
                json={"app_slug": "myapp", "scope": "register"}
            )

    # --- Backup & Restore ---

    @pytest.mark.asyncio
    async def test_hub_backup_list(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"backups": [{"id": 1, "created_at": "2025-01-01"}]}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_backup_list", arguments={"app_slug": "myapp"}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/apps/myapp/backup", method="GET")

    @pytest.mark.asyncio
    async def test_hub_backup_stats(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"total_backups": 42, "total_size_bytes": 1000}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_backup_stats", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/admin/backups/stats", method="GET")

    @pytest.mark.asyncio
    async def test_hub_backup_export_env(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)

        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"users": [], "apps": [], "settings": {}}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_backup_export_env", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/admin/backup/export", method="GET")

    @pytest.mark.asyncio
    async def test_hub_message_send(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)
        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"sent": True}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_message_send", arguments={"title": "Test", "target_usernames": ["user1"], "priority": "info"}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/messages/send", method="POST", json={"title": "Test", "target_usernames": ["user1"], "priority": "info"})

    @pytest.mark.asyncio
    async def test_hub_audit_logs(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)
        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"logs": []}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_audit_logs", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/audit/logs", method="GET")

    @pytest.mark.asyncio
    async def test_hub_docs_get(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)
        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"content": "## Section 1"}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_docs_get", arguments={"section": "auth"}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/docs/integration?section=auth", method="GET")

    @pytest.mark.asyncio
    async def test_hub_discover_services(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)
        with patch("hub_mcp.tools.hub_client.discover_services", new_callable=AsyncMock) as mock_disc:
            from unittest.mock import MagicMock
            mock_svc = MagicMock()
            mock_svc.slug = "svc1"
            mock_svc.name = "Service 1"
            mock_svc.api_url = "http://svc1:8000"
            mock_svc.is_healthy = True
            mock_disc.return_value = {"svc1": mock_svc}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_discover_services", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_disc.assert_called_once()

    @pytest.mark.asyncio
    async def test_hub_design_manifest(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)
        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"version": "1.0.0", "sha256": "abc"}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_design_manifest", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/design-system/manifest", method="GET")

    @pytest.mark.asyncio
    async def test_hub_admin_info(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)
        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"hostname": "hub", "version": "2.2.0"}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_admin_info", arguments={}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/admin/hub-info", method="GET")

    @pytest.mark.asyncio
    async def test_hub_raw_call(self, server):
        from hub_mcp.tools import register_all_tools
        register_all_tools(server)
        with patch("hub_mcp.tools.hub_client.call_hub_endpoint", new_callable=AsyncMock) as mock_call:
            mock_call.return_value = {"ok": True}
            req = CallToolRequest(
                method="tools/call",
                params=CallToolRequestParams(name="hub_raw_call", arguments={"method": "POST", "path": "/api/test", "body": {"key": "value"}}),
            )
            result = await server.request_handlers[CallToolRequest](req)
            mock_call.assert_called_once_with("/api/test", method="POST", json={"key": "value"})
