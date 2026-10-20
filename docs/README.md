# Documentation website

The site at <https://docs.portareos.org/> is built from `documentation/`
and the root README, known issues, roadmap and licence. Edit those files;
the build stages them temporarily, preserving their relative links.

To build and preview locally:

```sh
python3 -m venv /tmp/portareos-docs-venv
/tmp/portareos-docs-venv/bin/pip install -r docs/requirements.txt
/tmp/portareos-docs-venv/bin/python tools/build-docs.py
python3 -m http.server 8000 --directory site
```

Open <http://localhost:8000/>. The build rejects broken documentation links,
missing anchors and pages omitted from navigation. `site/` is ignored by Git.

The Documentation workflow checks pull requests and deploys changes on
`next`. In repository Settings → Pages, set the publishing source to
**GitHub Actions**, keep the custom domain **docs.portareos.org**, and enable
**Enforce HTTPS** once GitHub has issued its certificate. DNS must point
`docs.portareos.org` to `portare-ch.github.io` with a CNAME record.
