import { spawn } from 'child_process';
import { existsSync, writeFileSync, readFileSync, unlinkSync } from 'fs';
import { join } from 'path';

const PID_FILE = '.ralph/loop.pid';

/**
 * Check if a Ralph loop is currently running for a project
 */
export function isLoopRunning(projectPath: string): boolean {
  const pidFile = join(projectPath, PID_FILE);

  if (!existsSync(pidFile)) {
    return false;
  }

  try {
    const pid = parseInt(readFileSync(pidFile, 'utf-8').trim());

    // Check if process is still running
    process.kill(pid, 0);
    return true;
  } catch {
    // Process not running, clean up stale PID file
    try {
      unlinkSync(pidFile);
    } catch {
      // Ignore cleanup errors
    }
    return false;
  }
}

/**
 * Start a Ralph loop for a project
 */
export function startLoop(projectPath: string): {
  success: boolean;
  message: string;
  pid?: number;
} {
  // Check if PRD exists
  const prdPath = join(projectPath, '.ralph/prd.json');
  if (!existsSync(prdPath)) {
    return {
      success: false,
      message: 'No PRD found. Use /prd to create stories first.',
    };
  }

  // Check if already running
  if (isLoopRunning(projectPath)) {
    return {
      success: false,
      message: 'Loop already running. Use /loop to check status.',
    };
  }

  try {
    // Start Ralph loop in background
    const logFile = join(projectPath, '.ralph/loop.log');

    // Use npx agentic-loop run
    const child = spawn('npx', ['agentic-loop', 'run'], {
      cwd: projectPath,
      detached: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: {
        ...process.env,
        // Ensure Claude runs non-interactively
        CLAUDE_CODE_ENTRYPOINT: 'cli',
      },
    });

    // Write output to log file
    const logStream = require('fs').createWriteStream(logFile, { flags: 'a' });
    child.stdout?.pipe(logStream);
    child.stderr?.pipe(logStream);

    // Save PID
    const pidFile = join(projectPath, PID_FILE);
    writeFileSync(pidFile, child.pid!.toString());

    // Detach child process
    child.unref();

    return {
      success: true,
      message: `Loop started (PID: ${child.pid}). Use /loop to check progress.`,
      pid: child.pid,
    };
  } catch (error) {
    return {
      success: false,
      message: `Failed to start loop: ${error}`,
    };
  }
}

/**
 * Stop a running Ralph loop
 */
export function stopLoop(projectPath: string): {
  success: boolean;
  message: string;
} {
  const pidFile = join(projectPath, PID_FILE);

  if (!existsSync(pidFile)) {
    return {
      success: false,
      message: 'No loop running.',
    };
  }

  try {
    const pid = parseInt(readFileSync(pidFile, 'utf-8').trim());

    // Kill the process and its children
    try {
      // Kill process group (negative PID)
      process.kill(-pid, 'SIGTERM');
    } catch {
      // Try killing just the process
      process.kill(pid, 'SIGTERM');
    }

    // Clean up PID file
    unlinkSync(pidFile);

    return {
      success: true,
      message: 'Loop stopped.',
    };
  } catch (error) {
    // Clean up PID file even if kill failed
    try {
      unlinkSync(pidFile);
    } catch {
      // Ignore
    }

    return {
      success: false,
      message: `Error stopping loop: ${error}`,
    };
  }
}

/**
 * Get loop process info
 */
export function getLoopInfo(projectPath: string): {
  running: boolean;
  pid?: number;
  logTail?: string;
} {
  const pidFile = join(projectPath, PID_FILE);
  const logFile = join(projectPath, '.ralph/loop.log');

  const running = isLoopRunning(projectPath);
  let pid: number | undefined;
  let logTail: string | undefined;

  if (existsSync(pidFile)) {
    try {
      pid = parseInt(readFileSync(pidFile, 'utf-8').trim());
    } catch {
      // Ignore
    }
  }

  if (existsSync(logFile)) {
    try {
      // Get last 500 chars of log
      const content = readFileSync(logFile, 'utf-8');
      logTail = content.slice(-500);
    } catch {
      // Ignore
    }
  }

  return { running, pid, logTail };
}
