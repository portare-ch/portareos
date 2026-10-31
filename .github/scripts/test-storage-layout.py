#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Exercise storage migrations and generated tmpfiles against disposable data."""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "packages/portareos/sources/scripts"
MIGRATOR = SCRIPTS / "storage-migrate"
POST_UPDATE = ROOT / "packages/portareos/sources/post-update"
FUNCTIONS = ROOT / "distributions/PortareOS/config/functions"
DEFAULTS = ROOT / "packages/emulators/libretro/retroarch/sources/SM8550"
SCUMMVM_TOOL = ROOT / "packages/virtual/emulators/sources/Start ScummVM.sh"


class StorageLayoutTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="storage-layout-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.storage = self.root / "storage"
        self.storage.mkdir()
        self.env = dict(os.environ)
        if binary := os.environ.get("STORAGE_TEST_BUSYBOX"):
            applets = self.root / "applets"
            applets.mkdir()
            for name in ("find", "stat", "cp", "mv", "mkdir", "rmdir", "rm",
                         "sed", "sync", "ls", "tr", "readlink"):
                (applets / name).symlink_to(binary)
            self.env["PATH"] = str(applets) + os.pathsep + self.env["PATH"]

    def write(self, relative, content="save"):
        path = self.storage / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def run_script(self, script, env=None):
        return subprocess.run(["bash", str(script), str(self.storage)],
                              capture_output=True, text=True, env=env or self.env)

    def migrate(self):
        result = self.run_script(MIGRATOR)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {str(path.relative_to(self.storage)):
                os.readlink(path) if path.is_symlink() else path.read_bytes()
                for path in self.storage.rglob("*")
                if path.is_file() or path.is_symlink()}

    def test_bios_and_saves_move_without_overwriting(self):
        examples = {
            "roms/bios/dc/dc_boot.bin": "bios/dreamcast/dc/dc_boot.bin",
            "roms/bios/dc/vmu_save_A1.bin": "saves/dreamcast/vmu_save_A1.bin",
            "roms/bios/pcsx2/bios/ps2.bin": "bios/ps2/pcsx2/bios/ps2.bin",
            "roms/bios/gba_bios.bin": "bios/gba/gba_bios.bin",
            "roms/bios/bios_MD.bin": "bios/genesis/bios_MD.bin",
            "roms/bios/bios.sms": "bios/mastersystem/bios_U.sms",
            "roms/bios/neocd/neocd.bin": "bios/neocd/neocd/neocd.bin",
            "roms/bios/neogeo.zip": "bios/arcade/neogeo.zip",
            "roms/bios/PPSSPP/font.pgf": "bios/psp/PPSSPP/font.pgf",
            "roms/gb/nested/Game.srm": "saves/gb/Game.srm",
            "roms/gba/Game.rtc": "saves/gba/Game.rtc",
            "roms/nes/Game.sav": "saves/nes/Game.sav",
            "roms/segacd/Game.brm": "saves/segacd/Game.brm",
            "roms/psx/Game.mcd": "saves/psx/Game.mcd",
            "roms/saturn/smpc.bin": "saves/saturn/smpc.bin",
            "roms/naomi/Game.eeprom": "saves/naomi/reicast/Game.eeprom",
            "roms/arcade/nested/fbneo/Game.fs": "saves/arcade/fbneo/Game.fs",
            "roms/psp/PSP/SAVEDATA/Game/data.bin": "saves/psp/PSP/SAVEDATA/Game/data.bin",
            "roms/gamecube/User/GC/card.raw": "saves/gamecube/User/GC/card.raw",
            "roms/wii/User/Wii/save.bin": "saves/wii/User/Wii/save.bin",
            "roms/ps2/Mcd001.ps2": "saves/ps2/Mcd001.ps2",
        }
        for number, source in enumerate(examples):
            self.write(source, str(number))
        self.write("roms/bios/unknown.bin", "unknown")
        conflict = self.write("roms/gb/conflict.srm", "old")
        target = self.write("saves/gb/conflict.srm", "new")
        output = self.migrate()
        for number, (source, destination) in enumerate(examples.items()):
            with self.subTest(source=source):
                self.assertFalse((self.storage / source).exists())
                self.assertEqual((self.storage / destination).read_text(), str(number))
        self.assertEqual(conflict.read_text(), "old")
        self.assertEqual(target.read_text(), "new")
        self.assertIn("is taken", output.stdout)
        self.assertEqual((self.storage / "roms/bios/unknown.bin").read_text(), "unknown")
        once = self.snapshot()
        self.migrate()
        self.assertEqual(self.snapshot(), once)

    def test_fds_saves_after_system_merge(self):
        self.write("roms/fds/Disk.FDS", "disk")
        self.write("roms/fds/Disk.ips", "disk save")
        self.write("roms/nes/Cartridge.nes", "cart")
        patch = self.write("roms/nes/Cartridge.ips", "ROM patch")
        result = self.run_script(SCRIPTS / "system-merge")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.migrate()
        self.assertEqual((self.storage / "saves/nes/Disk.ips").read_text(), "disk save")
        self.assertEqual(patch.read_text(), "ROM patch")

    def test_explicit_scummvm_savepath_is_preserved(self):
        config = "[scummvm]\nsavepath=/storage/custom-saves\n"
        self.write("roms/bios/scummvm.ini", config)
        sci = self.write("custom-saves/kq6.000", "SCI save")
        scumm = self.write("custom-saves/monkey.s00", "SCUMM save")
        self.migrate()
        self.assertEqual((self.storage / "bios/scummvm/scummvm.ini").read_text(), config)
        self.assertEqual(sci.read_text(), "SCI save")
        self.assertEqual(scumm.read_text(), "SCUMM save")

    def test_palette_copy_failure_preserves_source_for_retry(self):
        source = self.write("roms/bios/palettes/Game.pal", "palette")
        result = self.run_script(MIGRATOR, self.failing_command("cp", "palettes"))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(source.read_text(), "palette")
        self.migrate()
        for system in ("gb", "gbc"):
            self.assertEqual((self.storage / f"bios/{system}/palettes/Game.pal").read_text(), "palette")

    def test_custom_core_links_are_retained(self):
        custom = self.storage / "roms/bios/pcsx2/memcards"
        custom.parent.mkdir(parents=True)
        custom.symlink_to("/storage/custom-memory-cards")
        resources = custom.parent / "resources"
        resources.symlink_to("/usr/share/armsx2/resources")
        self.migrate()
        self.assertTrue(custom.is_symlink())
        self.assertEqual(os.readlink(custom), "/storage/custom-memory-cards")
        self.assertFalse(resources.is_symlink())

    def test_scummvm_tool_uses_its_system_storage(self):
        capture = self.root / "arguments"
        retroarch = self.root / "retroarch"
        retroarch.write_text('#!/bin/bash\nprintf "%s\\n" "$@" >"$CAPTURE"\n')
        retroarch.chmod(0o755)
        script = self.root / "scummvm-tool.sh"
        text = SCUMMVM_TOOL.read_text().replace("source /etc/profile", "set_kill() { :; }")
        text = text.replace("/usr/bin/retroarch", str(retroarch))
        text = text.replace("/usr/config/retroarch/", str(DEFAULTS) + "/")
        text = text.replace("/storage/", str(self.storage) + "/")
        script.write_text(text)
        result = self.run_script(script, dict(self.env, CAPTURE=str(capture)))
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = capture.read_text().splitlines()
        self.assertIn("--appendconfig", arguments)
        config = Path(arguments[arguments.index("--appendconfig") + 1]).read_text()
        self.assertIn('system_directory = "/storage/bios/scummvm"', config)
        self.assertIn('savefile_directory = "/storage/saves/scummvm"', config)
        self.assertIn('savefiles_in_content_dir = "false"', config)

    def test_per_launch_paths_use_the_content_system(self):
        source = (SCRIPTS / "setsettings.sh").read_text()
        function = re.search(r"function set_storage\(\) \{.*?\n\}", source, re.S).group()
        script = self.root / "settings.sh"
        script.write_text(function.replace('"/storage/', '"' + str(self.storage) + '/') +
                          '\nadd_setting() { printf "%s=%s\\n" "$2" "$3"; }\nset_storage\n')
        for platform, rom, folder in (("nes", "/storage/roms/nes/nested/Game.fds", "nes"),
                                      ("fbn", "/storage/roms/fbneo/Game.zip", "fbneo"),
                                      ("psx", "/tmp/Game.chd", "psx")):
            with self.subTest(rom=rom):
                env = dict(self.env, ROMS_DIR="/storage/roms", ROM_PATH=rom, PLATFORM=platform)
                result = self.run_script(script, env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), [
                    f"system_directory={self.storage}/bios/{folder}",
                    f"savefile_directory={self.storage}/saves/{folder}",
                    "savefiles_in_content_dir=false",
                ])

    def update_fragment(self):
        text = POST_UPDATE.read_text()
        start = text.index("### One storage layout for every emulator")
        end = text.index("### ScummVM's core looks", start)
        fragment = text[start:end].replace("/storage/", str(self.storage) + "/")
        fragment = fragment.replace("/usr/bin/storage-migrate", 'bash "$MIGRATOR" "$STORAGE"')
        script = self.root / "update.sh"
        script.write_text(fragment)
        return script

    def failing_command(self, name, match):
        wrapper = self.root / "fail-bin"
        wrapper.mkdir()
        real = shutil.which(name, path=self.env["PATH"])
        script = wrapper / name
        script.write_text(f'#!/bin/bash\nfor arg; do\n'
                          f'  [[ "$arg" != *{match}* ]] || exit 1\ndone\n'
                          f'exec "{real}" "$@"\n')
        script.chmod(0o755)
        return dict(self.env, PATH=str(wrapper) + os.pathsep + self.env["PATH"])

    def test_failed_move_is_retried_before_marking_complete(self):
        source = self.write("roms/bios/gb_bios.bin", "BIOS")
        script = self.update_fragment()
        env = dict(self.env, MIGRATOR=str(MIGRATOR), STORAGE=str(self.storage),
                   LOG=str(self.root / "boot.log"))
        failed = dict(env, PATH=self.failing_command("mv", "gb_bios.bin")["PATH"])
        marker = self.storage / ".config/system/.migrations/storage-layout"
        self.run_script(script, failed)
        self.assertFalse(marker.exists(), (self.root / "boot.log").read_text())
        self.assertEqual(source.read_text(), "BIOS")
        self.run_script(script, env)
        self.assertTrue(marker.exists())
        self.assertEqual((self.storage / "bios/gb/gb_bios.bin").read_text(), "BIOS")

    @unittest.skipUnless(Path("/dev/shm").is_dir(), "needs another filesystem")
    def test_cross_filesystem_copy_failure_is_reported_and_resumes(self):
        temporary = tempfile.TemporaryDirectory(prefix="storage-layout-", dir="/dev/shm")
        self.addCleanup(temporary.cleanup)
        (self.storage / "saves").symlink_to(temporary.name)
        source = self.write("roms/gb/Game.srm", "complete save")
        failed = self.run_script(MIGRATOR, self.failing_command("cp", "Game.srm"))
        self.assertNotEqual(failed.returncode, 0, failed.stdout + failed.stderr)
        self.assertEqual(source.read_text(), "complete save")
        self.assertFalse((self.storage / "saves/gb/Game.srm").exists())
        self.migrate()
        self.assertFalse(source.exists())
        self.assertEqual((self.storage / "saves/gb/Game.srm").read_text(), "complete save")
        self.assertFalse((self.storage / "saves/gb/Game.srm.part").exists())

    def test_generated_directory_rules_are_unique_and_aliases_parse(self):
        functions = FUNCTIONS.read_text().split("# config.xml parsing")[0]
        script = self.root / "directories.sh"
        script.write_text(functions + '\nadd_system_dir /storage/bios/dreamcast\n'
                          'add_system_dir /storage/bios/dreamcast\n'
                          'add_system_link /storage/bios/naomi dreamcast\n')
        cache = self.root / "cache"
        result = self.run_script(script, dict(self.env, ESTMP=str(cache)))
        self.assertEqual(result.returncode, 0, result.stderr)
        rules = (cache / "system-dirs.conf").read_text().splitlines()
        self.assertEqual(len(rules), 2, rules)
        self.assertEqual(rules[1].split(), ["L", "/storage/bios/naomi", "-", "-", "-", "-", "dreamcast"])
        if shutil.which("systemd-tmpfiles"):
            applied = self.root / "apply.conf"
            applied.write_text("\n".join(rules).replace(" root root ", f" {os.getuid()} {os.getgid()} ") + "\n")
            result = subprocess.run(["systemd-tmpfiles", "--create", "--root=" + str(self.root),
                                     str(applied)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((self.storage / "bios/dreamcast").is_dir())
            self.assertEqual(os.readlink(self.storage / "bios/naomi"), "dreamcast")

    @unittest.skipUnless(shutil.which("xmlstarlet") and shutil.which("systemd-tmpfiles"),
                         "needs xmlstarlet and systemd-tmpfiles")
    def test_emulator_recipe_generates_the_canonical_storage_layout(self):
        recipe = ROOT / "packages/virtual/emulators/package.mk"
        script = self.root / "generate.sh"
        script.write_text(FUNCTIONS.read_text().split("# config.xml parsing")[0] +
                          '\nsource "$RECIPE"\n'
                          'clean_es_cache() { ESTMP="$CACHE"; mkdir -p "$ESTMP"; }\n'
                          'clean_doc_cache() { :; }\nstart_system_doc() { :; }\n'
                          'mk_system_doc() { :; }\n'
                          'add_system_doc() { :; }\nadd_emu_doc() { :; }\n'
                          'install_script() { :; }\nmakeinstall_target\n')
        cache = self.root / "cache"
        env = dict(self.env, ROOT=str(ROOT), DEVICE="SM8550", ARCH="aarch64",
                   RECIPE=str(recipe), CACHE=str(cache), INSTALL=str(self.root / "install"))
        result = self.run_script(script, env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rules = (cache / "system-dirs.conf").read_text()
        combined = self.root / "all.conf"
        for core in ("armsx2", "dolphin", "flycast"):
            rules += (ROOT / f"packages/emulators/libretro/{core}-lr/tmpfiles.d/z_06_{core}.conf").read_text()
        combined.write_text(rules.replace(" root root ", f" {os.getuid()} {os.getgid()} "))
        result = subprocess.run(["systemd-tmpfiles", "--create", "--root=" + str(self.root),
                                 str(combined)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for system in ("nes", "genesis", "ps2", "xbox", "scummvm", "gamecube", "wii"):
            self.assertTrue((self.storage / f"bios/{system}").is_dir(), system)
            self.assertTrue((self.storage / f"saves/{system}").is_dir(), system)
        for system, target in (("naomi", "dreamcast"), ("atomiswave", "dreamcast"), ("neogeo", "arcade")):
            self.assertEqual(os.readlink(self.storage / f"bios/{system}"), target)
        self.assertFalse((self.storage / "bios/megadrive").exists())
        self.assertFalse((self.storage / "saves/movies").exists())
        self.assertFalse((self.storage / "saves/music").exists())
        self.assertEqual(os.readlink(self.storage / "bios/ps2/pcsx2/memcards"), "/storage/saves/ps2")
        self.assertEqual(os.readlink(self.storage / "bios/dreamcast/dc/vmu_save_A1.bin"),
                         "/storage/saves/dreamcast/vmu_save_A1.bin")


if __name__ == "__main__":
    unittest.main()
