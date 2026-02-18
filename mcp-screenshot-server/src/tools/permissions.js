import { checkPermissions } from './utils.js';

/**
 * MCP Tool: check_permissions
 * Checks if required macOS permissions are granted
 */
export const checkPermissionsTool = {
    name: 'check_permissions',
    description: 'Check if required macOS permissions (Screen Recording, Accessibility) are granted.',
    inputSchema: {
        type: 'object',
        properties: {}
    }
};

/**
 * Handler for check_permissions tool
 */
export async function handleCheckPermissions() {
    try {
        const permissions = await checkPermissions();
        
        const allGranted = permissions.screenRecording && permissions.accessibility;
        
        const response = {
            success: true,
            all_granted: allGranted,
            permissions: {
                screen_recording: {
                    granted: permissions.screenRecording,
                    required: true,
                    instructions: permissions.screenRecording 
                        ? null 
                        : 'Go to: System Preferences → Security & Privacy → Screen Recording'
                },
                accessibility: {
                    granted: permissions.accessibility,
                    required: true,
                    instructions: permissions.accessibility 
                        ? null 
                        : 'Go to: System Preferences → Security & Privacy → Accessibility'
                }
            }
        };
        
        if (!allGranted) {
            response.message = 'Some permissions are missing. Please grant them to use screenshot capture.';
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
                        code: 'PERMISSION_CHECK_FAILED'
                    }, null, 2)
                }
            ],
            isError: true
        };
    }
}
