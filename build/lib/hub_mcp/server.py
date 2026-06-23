"""
Serveur MCP stdio exposant les outils Hub.
Point d'entrée: python -m hub_mcp.server
"""
import asyncio
import sys
import os

# Ajouter le dossier parent au path pour importer backend.*
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from mcp.server import Server
from mcp.server.stdio import stdio_server
from hub_mcp.tools import register_all_tools


def main():
    server = Server("hub-tools")
    register_all_tools(server)

    async def run():
        async with stdio_server() as (read, write):
            await server.run(read, write, server.create_initialization_options())

    asyncio.run(run())


if __name__ == "__main__":
    main()
