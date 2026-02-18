#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

import { captureWindowTool, handleCaptureWindow } from './tools/capture.js';
import { listWindowsTool, handleListWindows } from './tools/list.js';
import { checkPermissionsTool, handleCheckPermissions } from './tools/permissions.js';

/**
 * MCP Screenshot Server
 * Provides tools for capturing window screenshots on macOS
 */
class ScreenshotServer {
    constructor() {
        this.server = new Server(
            {
                name: 'mcp-screenshot-server',
                version: '1.0.0',
            },
            {
                capabilities: {
                    tools: {},
                },
            }
        );

        this.setupHandlers();
        this.setupErrorHandling();
    }

    setupHandlers() {
        // List available tools
        this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
            tools: [
                captureWindowTool,
                listWindowsTool,
                checkPermissionsTool
            ],
        }));

        // Handle tool calls
        this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
            const { name, arguments: args } = request.params;

            try {
                switch (name) {
                    case 'capture_window':
                        return await handleCaptureWindow(args);
                    
                    case 'list_windows':
                        return await handleListWindows(args);
                    
                    case 'check_permissions':
                        return await handleCheckPermissions(args);
                    
                    default:
                        throw new Error(`Unknown tool: ${name}`);
                }
            } catch (error) {
                return {
                    content: [
                        {
                            type: 'text',
                            text: JSON.stringify({
                                success: false,
                                error: error.message,
                                code: 'TOOL_EXECUTION_FAILED'
                            }, null, 2)
                        }
                    ],
                    isError: true
                };
            }
        });
    }

    setupErrorHandling() {
        this.server.onerror = (error) => {
            console.error('[MCP Error]', error);
        };

        process.on('SIGINT', async () => {
            await this.server.close();
            process.exit(0);
        });
    }

    async run() {
        const transport = new StdioServerTransport();
        await this.server.connect(transport);
        console.error('MCP Screenshot Server running on stdio');
    }
}

// Start server
const server = new ScreenshotServer();
server.run().catch((error) => {
    console.error('Failed to start server:', error);
    process.exit(1);
});
