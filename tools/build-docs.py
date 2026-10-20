#!/usr/bin/env python3
"""Build the documentation site from the repository's existing Markdown."""

import argparse
import logging
from pathlib import Path
import shutil
import sys
import tempfile

from mkdocs.commands.build import build
from mkdocs.config import load_config
from mkdocs.exceptions import MkDocsException


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site-dir", default="site", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.site_dir.resolve()
    if root.is_relative_to(output) or (
        output.is_relative_to(root) and output != root / "site"
    ):
        parser.error("--site-dir must be site/ or a directory outside the repository")

    # Stage only public documentation, never the build tree or local settings.
    with tempfile.TemporaryDirectory(prefix="portareos-docs-") as temporary:
        source = Path(temporary)
        shutil.copytree(root / "documentation", source / "documentation")
        for name in ("README.md", "BUGS.md", "ROADMAP.md", "LICENSE.md"):
            shutil.copy2(root / name, source / name)
        shutil.copy2(root / "docs/CNAME", source / "CNAME")
        logo = Path("distributions/PortareOS/logos/portareos-logo.png")
        (source / logo).parent.mkdir(parents=True)
        shutil.copy2(root / logo, source / logo)

        config = load_config(
            config_file=str(root / "docs/mkdocs.yml"),
            docs_dir=str(source),
            site_dir=str(output),
            strict=True,
        )
        build(config)


if __name__ == "__main__":
    try:
        main()
    except MkDocsException as error:
        sys.exit(str(error))
