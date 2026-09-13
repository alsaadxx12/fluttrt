import os
import zipfile

src_dir = r"c:\Users\Medinat AlElm\Desktop\youtube"
desktop_dir = r"c:\Users\Medinat AlElm\Desktop"
zip_path = os.path.join(desktop_dir, "CINEBALL_Mac.zip")

exclude_dirs = {
    ".dart_tool",
    "build",
    ".git",
    ".idea",
    ".vscode",
    "scratch",
    ".agents",
    ".claude",
    ".netlify",
}
exclude_exts = {".exe", ".zip", ".apk", ".mp4", ".webm"}

print(f"Creating clean Mac archive at: {zip_path}")
count = 0
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk(src_dir):
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        for file in files:
            ext = os.path.splitext(file)[1].lower()
            if ext in exclude_exts:
                continue
            if root == src_dir and ext == ".png":
                continue
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, src_dir)
            zipf.write(full_path, os.path.join("youtube", rel_path))
            count += 1

size_mb = os.path.getsize(zip_path) / (1024 * 1024)
print(f"SUCCESS: Zipped {count} files. Total size: {size_mb:.2f} MB")
