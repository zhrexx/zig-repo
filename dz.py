# Why i use python when i hate it? because its simpler than writing platform-dependent C code
import sys
import platform
import requests
from tqdm import tqdm

def download_zig(version, os_name, arch ):
    ending = "zip" if os_name == "windows" else "tar.xz"
    url = f"https://github.com/zhrexx/zig-repo/releases/download/RELEASE/zig-{arch}-{os_name}-{version}.{ending}"
    dest = url.split('/')[-1]
    with requests.get(url, stream=True) as r:
        r.raise_for_status()
        total = int(r.headers.get("content-length", 0))
        chunk_size = 8192

        with open(dest, "wb") as f, tqdm(
                total=total,
                unit="B",
                unit_scale=True,
                unit_divisor=1024,
                desc=dest
        ) as bar:
            for chunk in r.iter_content(chunk_size=chunk_size):
                if chunk:
                    f.write(chunk)
                    bar.update(len(chunk))

def main() -> int:
    args = sys.argv

    if len(args) <= 1:
        print(f"ERROR: Usage: {args[0]} <version> [os|native] [arch|native]")
        return 1

    version = args[1]

    os_name = platform.system().lower()
    arch = platform.machine().lower()

    if len(args) >= 3:
        os_name = args[2].lower()

    if len(args) == 4:
        arch = args[3].lower()

    if os_name == "native":
        os_name = platform.system().lower()

    if arch == "native":
        arch = platform.machine().lower()

    print(f"Downloading Zig {version} for:")
    print("os:", os_name)
    print("arch:", arch)

    download_zig(version, os_name, arch)
    
    return 0

if __name__ == "__main__":
    exit(main())
