#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Run the configuration-sync part of post-update against temporary storage."""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
POST_UPDATE = ROOT / "packages/portareos/sources/post-update"
DEFAULTS = ROOT / "packages/emulators/libretro/retroarch/sources/SM8550"


def options(path):
    return {
        key.strip(): value.strip()
        for line in path.read_text().splitlines()
        if not line.lstrip().startswith("#") and "=" in line
        for key, _, value in [line.partition("=")]
    }


class RetroArchUpdateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="retroarch-update-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.image = self.root / "usr/config/retroarch"
        self.user = self.root / "storage/.config/retroarch"
        self.user.mkdir(parents=True)
        self.write(self.root / "usr/config", "modules/test.sh", "#!/bin/sh\n")
        (self.root / "tmp").mkdir()
        shutil.copytree(DEFAULTS, self.image)

        # Include the general --ignore-existing pass: it also touches RetroArch.
        script = POST_UPDATE.read_text()
        start = script.index("### Config files that are new in this image.")
        end = script.index("### Apply developer ssh keys")
        script = script[start:end]
        script = re.sub(
            r"/(?:usr/config|storage|tmp)/",
            lambda match: str(self.root) + match[0],
            script,
        )
        self.script = self.root / "post-update-configs.sh"
        self.script.write_text('LOG="$1"\ntocon() { :; }\n' + script)

    def update(self):
        result = subprocess.run(
            ["bash", str(self.script), str(self.root / "boot.log")],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "", result.stderr)

    def write(self, base, relative, content):
        path = base / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_existing_overrides_survive(self):
        saved = {
            "config/Flycast/Flycast.cfg": '# Custom core override\naudio_out_rate = "48000"\n',
            "config/Gambatte/gbc.opt": 'gambatte_mix_frames = "disabled"\n',
            "config/ParaLLEl N64/ParaLLEl N64.opt": 'parallel-n64-gfxplugin = "angrylion"\n',
            "config/Flycast/dreamcast.cfg": 'video_scale_integer = "false"\n',
            "config/Flycast/Game Name.cfg": 'video_shader_enable = "false"\n',
            "config/Custom Core/Custom Core.cfg": 'video_smooth = "true"\n',
            "config.pre-refresh/Flycast/Flycast.cfg": "old backup\n",
        }
        for relative, content in saved.items():
            self.write(self.user, relative, content)
            if not relative.startswith(("config.pre-refresh/", "config/Custom Core/")):
                self.write(self.image, relative, '# Updated image\nsetting = "default"\n')
        self.write(self.user, "retroarch.cfg", "old main config\n")

        self.update()
        for relative, content in saved.items():
            with self.subTest(path=relative):
                self.assertEqual((self.user / relative).read_text(), content)
        self.assertEqual(
            (self.user / "retroarch.cfg").read_bytes(),
            (self.image / "retroarch.cfg").read_bytes(),
        )
        self.assertEqual((self.user / "retroarch.cfg.pre-refresh").read_text(), "old main config\n")

    def test_global_options_keep_values_and_add_missing_keys(self):
        saved = (
            '# My settings\n  # dolphin_efb_scale = "8"\n'
            '\tflycast_internal_resolution\t= "1280x960"\n'
            'user_only = "a=b # value"\n'
            'gambatte_gb_internal_palette = ""'
        )
        path = self.write(self.user, "retroarch-core-options.cfg", saved)
        expected = options(self.image / path.name) | options(path)

        self.update()
        self.assertTrue(path.read_text().startswith(saved + "\n"))
        self.assertEqual(options(path), expected)
        once = path.read_bytes()
        self.update()
        self.assertEqual(path.read_bytes(), once)

    def test_empty_and_comment_only_options_get_defaults(self):
        for content in ("", "# No saved options", "\n# dolphin_efb_scale = 8\n"):
            with self.subTest(content=content):
                path = self.write(self.user, "retroarch-core-options.cfg", content)
                self.update()
                self.assertEqual(options(path), options(self.image / path.name))
                self.assertTrue(path.read_text().startswith(content))

    def test_fresh_install_gets_all_defaults(self):
        self.update()
        for source in self.image.rglob("*"):
            if source.is_file():
                relative = source.relative_to(self.image)
                with self.subTest(path=relative):
                    self.assertEqual((self.user / relative).read_bytes(), source.read_bytes())

    def test_later_update_adds_files_without_replacing_saved_ones(self):
        self.update()
        override = self.write(self.user, "config/PPSSPP/PPSSPP.cfg", "# Empty override\n")
        empty = self.write(self.user, "config/Gambatte/gbc.opt", "")
        core_options = self.user / "retroarch-core-options.cfg"
        saved_options = core_options.read_text()
        new = self.write(self.image, "config/New Core/New Core.cfg", 'audio_out_rate = "0"\n')
        with (self.image / "retroarch-core-options.cfg").open("a") as target:
            target.write('\nnew_core_option = "enabled"\n')
        self.write(self.image, "config/PPSSPP/PPSSPP.cfg", 'video_smooth = "true"\n')

        self.update()
        self.assertEqual(override.read_text(), "# Empty override\n")
        self.assertEqual(empty.read_bytes(), b"")
        self.assertEqual((self.user / new.relative_to(self.image)).read_bytes(), new.read_bytes())
        self.assertEqual(core_options.read_text(), saved_options + 'new_core_option = "enabled"\n')
        once = core_options.read_bytes()
        self.update()
        self.assertEqual(core_options.read_bytes(), once)


if __name__ == "__main__":
    unittest.main()
