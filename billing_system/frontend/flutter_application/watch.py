import os
import sys
import time
import signal

def watch_dir(directory, callback, pid_file):
    # Dictionary to keep track of file modification times
    files = {}
    
    # Initial scan
    for root, dirs, filenames in os.walk(directory):
        for f in filenames:
            if f.endswith('.dart'):
                path = os.path.join(root, f)
                try:
                    files[path] = os.path.getmtime(path)
                except OSError:
                    pass

    print(f"[Watcher] Monitoring {directory} for changes...", flush=True)
    
    # Loop and check for modifications or additions
    while True:
        time.sleep(1.0)
        
        # Check if pid file exists, if not, wait
        if not os.path.exists(pid_file):
            continue
            
        changed = False
        new_files = {}
        for root, dirs, filenames in os.walk(directory):
            for f in filenames:
                if f.endswith('.dart'):
                    path = os.path.join(root, f)
                    try:
                        mtime = os.path.getmtime(path)
                        new_files[path] = mtime
                        if path not in files:
                            # New file added
                            changed = True
                        elif files[path] != mtime:
                            # File modified
                            changed = True
                    except OSError:
                        pass
        
        # Check for deleted files
        if not changed:
            for path in files:
                if path not in new_files:
                    changed = True
                    break
                    
        files = new_files
        
        if changed:
            print("[Watcher] Change detected. Triggering hot reload...", flush=True)
            callback(pid_file)

def trigger_reload(pid_file):
    try:
        with open(pid_file, 'r') as f:
            pid = int(f.read().strip())
        # Send SIGUSR1 to the process (triggers Flutter Hot Reload)
        os.kill(pid, signal.SIGUSR1)
        print(f"[Watcher] Sent SIGUSR1 (Hot Reload) to Flutter PID {pid}", flush=True)
    except Exception as e:
        # Occasionally the pid file is empty or writing, ignore temporary errors
        pass

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python watch.py <directory_to_watch> <pid_file_path>")
        sys.exit(1)
        
    watch_dir(sys.argv[1], trigger_reload, sys.argv[2])
