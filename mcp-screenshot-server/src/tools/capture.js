import { findWindow, captureWindow, imageToBase64, cleanupFile } from './utils.js';

/**
 * MCP Tool: capture_window
 * Captures a screenshot of a specific window
 */
export const captureWindowTool = {
    name: 'capture_window',
    description: 'Capture a screenshot of a specific window by name or ID. Returns image data or file path.',
    inputSchema: {
        type: 'object',
        properties: {
            window_name: {
                type: 'string',
                description: 'Name of the application window to capture (e.g., "World of Warcraft")'
            },
            window_id: {
                type: 'number',
                description: 'Window ID to capture (alternative to window_name)'
            },
            format: {
                type: 'string',
                enum: ['png', 'jpg'],
                description: 'Image format (default: png)',
                default: 'png'
            },
            return_base64: {
                type: 'boolean',
                description: 'Return image as base64 string instead of file path (default: false)',
                default: false
            }
        },
        oneOf: [
            { required: ['window_name'] },
            { required: ['window_id'] }
        ]
    }
};

/**
 * Handler for capture_window tool
 */
export async function handleCaptureWindow(args) {
    const { window_name, window_id, format = 'png', return_base64 = false } = args;
    
    try {
        // Find window if name provided
        let targetWindowId = window_id;
        let windowInfo = null;
        
        if (!targetWindowId && window_name) {
            windowInfo = await findWindow(window_name);
            targetWindowId = windowInfo.id;
        }
        
        if (!targetWindowId) {
            throw new Error('Either window_name or window_id must be provided');
        }
        
        // Capture screenshot
        const capture = await captureWindow(targetWindowId, { format });
        
        // Prepare response
        const response = {
            success: true,
            window_id: targetWindowId,
            window_name: windowInfo?.name || 'Unknown',
            timestamp: new Date().toISOString(),
            format: format
        };
        
        if (return_base64) {
            // Return base64 encoded image
            response.image_data = await imageToBase64(capture.path);
            response.size_bytes = capture.size;
            
            // Clean up temp file
            await cleanupFile(capture.path);
        } else {
            // Return file path
            response.image_path = capture.path;
            response.size_bytes = capture.size;
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
                        code: getErrorCode(error.message)
                    }, null, 2)
                }
            ],
            isError: true
        };
    }
}

/**
 * Get error code from error message
 */
function getErrorCode(message) {
    if (message.includes('not running')) return 'WINDOW_NOT_FOUND';
    if (message.includes('has no windows')) return 'NO_WINDOWS';
    if (message.includes('permission')) return 'PERMISSION_DENIED';
    return 'CAPTURE_FAILED';
}
