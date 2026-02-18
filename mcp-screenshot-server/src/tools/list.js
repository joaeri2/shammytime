import { listWindows } from './utils.js';

/**
 * MCP Tool: list_windows
 * Lists all available windows that can be captured
 */
export const listWindowsTool = {
    name: 'list_windows',
    description: 'List all available windows that can be captured. Optionally filter by application name.',
    inputSchema: {
        type: 'object',
        properties: {
            application_name: {
                type: 'string',
                description: 'Filter windows by application name (e.g., "World of Warcraft")'
            },
            include_all_apps: {
                type: 'boolean',
                description: 'Include windows from all applications (default: true if no application_name provided)',
                default: true
            }
        }
    }
};

/**
 * Handler for list_windows tool
 */
export async function handleListWindows(args) {
    const { application_name, include_all_apps = true } = args;
    
    try {
        // List windows
        const windows = await listWindows(application_name || (include_all_apps ? null : undefined));
        
        // Prepare response
        const response = {
            success: true,
            count: windows.length,
            windows: windows.map(w => ({
                id: w.id,
                name: w.name,
                application: w.application,
                bounds: w.bounds || null
            }))
        };
        
        if (application_name) {
            response.filter = application_name;
        }
        
        return {
            content: [
                {
                    type: 'text',
                    text: JSON.stringify(response, null, 2)
                }
            ]
        };
        
    } catch (error) {
        return {
            content: [
                {
                    type: 'text',
                    text: JSON.stringify({
                        success: false,
                        error: error.message,
                        code: 'LIST_FAILED'
                    }, null, 2)
                }
            ],
            isError: true
        };
    }
}
