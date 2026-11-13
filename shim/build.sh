#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CC="clang --target=aarch64-unknown-none-elf"
OBJCOPY="llvm-objcopy"
CFLAGS="-O2 -ffreestanding -nostdlib -fpie -fno-plt -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"

mkdir -p out
for f in start.S shim.c console.c mmu.c fdt.c loader.c ufs.c; do
    $CC $CFLAGS -c $f -o out/${f%.*}.o
done

abs=$(llvm-readelf -r out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }

$CC $CFLAGS -fuse-ld=lld -static -T shim.ld -Wl,--build-id=none -Wl,-N \
    out/start.o out/shim.o out/console.o out/mmu.o out/fdt.o out/loader.o out/ufs.o -o out/shim.elf

$OBJCOPY -O binary out/shim.elf out/Image
size=$(llvm-nm out/shim.elf | awk '$3=="_end"{print strtonum("0x"$1)}')
truncate -s "$size" out/Image

if [ -n "${1:-}" ]; then
    cp "$1" out/ramdisk.bin
else
    (cd out && rm -rf rd && mkdir rd && cd rd && find . | cpio -o -H newc --quiet | gzip -9 > ../ramdisk.bin)
fi

mkbootimg --header_version 2 --kernel out/Image --ramdisk out/ramdisk.bin \
    --dtb ../dtb/boot_unpacked/dtb --base 0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
    --tags_offset 0x100 --dtb_offset 0x1f00000 --pagesize 4096 \
    --os_version 17.0.0 --os_patch_level 2035-06 \
    --cmdline "console=null" -o out/shim-boot.img

clang -O1 -Wall -o out/host_test console.c host_test.c && ./out/host_test
ls -lh out/Image out/shim-boot.img
