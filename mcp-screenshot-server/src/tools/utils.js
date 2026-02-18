import { execa } from 'execa';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFile, unlink } from 'fs/promises';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SCRIPTS_DIR = join(__dirname, '../../scripts');

/**
 * Find a window by application name
 * @param {string} appName - Application name (e.g., "World of Warcraft")
 * @returns {Promise<{id: number, name: string, application: string}>}
 */
export async function findWindow(appName) {
    try {
        const scriptPath = join(SCRIPTS_DIR, 'find_window.applescript');
        const { stdout } = await execa('osascript', [scriptPath, appName]);
        return JSON.parse(stdout);
    } catch (error) {
        if (error.stderr?.includes('is not running')) {
            throw new Error(`Application '${appName}' is not running`);
        } else if (error.stderr?.includes('has no windows')) {
            throw new Error(`Application '${appName}' has no windows`);
        }
        throw new Error(`Failed to find window: ${error.message}`);
    }
}

/**
 * List all windows for an application (or all applications)
 * @param {string} [appName] - Optional application name filter
 * @returns {Promise<Array<{id: number, name: string, application: string, bounds?: object}>>}
 */
export async function listWindows(appName = null) {
    try {
        const scriptPath = join(SCRIPTS_DIR, 'list_windows.applescript');
        const args = appName ? [scriptPath, appName] : [scriptPath];
        const { stdout } = await execa('osascript', args);
        return JSON.parse(stdout);
    } catch (error) {
        throw new Error(`Failed to list windows: ${error.message}`);
    }
}

/**
 * Capture a screenshot of a window
 * @param {number} windowId - Window ID to capture
 * @param {object} options - Capture options
 * @param {string} options.format - Image format (png, jpg)
 * @param {string} options.outputPath - Output file path
 * @returns {Promise<{path: string, size: number}>}
 */
export async function captureWindow(windowId, options = {}) {
    const format = options.format || 'png';
    const outputPath = options.outputPath || `/tmp/mcp_screenshot_${Date.now()}.${format}`;
    
    try {
        // screencapture -l <windowID> -x -o <output>
        // -l: window ID
        // -x: no sound
        // -o: open in Preview (we skip this)
        await execa('screencapture', ['-l', String(windowId), '-x', outputPath]);
        
        // Get file size
        const stats = await readFile(outputPath);
        
        return {
            path: outputPath,
            size: stats.length
        };
    } catch (error) {
        throw new Error(`Failed to capture window: ${error.message}`);
    }
}

/**
 * Check if required permissions are granted
 * @returns {Promise<{screenRecording: boolean, accessibility: boolean}>}
 */
export async function checkPermissions() {
    const scriptPath = join(SCRIPTS_DIR, 'check_permissions.sh');
    
    const results = {
        screenRecording: false,
        accessibility: false
    };
    
    try {
        await execa('bash', [scriptPath, 'screen_recording']);
        results.screenRecording = true;
    } catch {
        results.screenRecording = false;
    }
    
    try {
        await execa('bash', [scriptPath, 'accessibility']);
        results.accessibility = true;
    } catch {
        results.accessibility = false;
    }
    
    return results;
}

/**
 * Convert image to base64
 * @param {string} imagePath - Path to image file
 * @returns {Promise<string>}
 */
export async function imageToBase64(imagePath) {
    const buffer = await readFile(imagePath);
    return buffer.toString('base64');
}

/**
 * Clean up temporary file
 * @param {string} filePath - Path to file to delete
 */
export async function cleanupFile(filePath) {
    try {
        await unlink(filePath);
    } catch (error) {
        // Ignore errors (file might not exist)
    }
}
