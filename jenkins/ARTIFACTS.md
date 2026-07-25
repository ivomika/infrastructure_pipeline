# Immutable artifact sources

Every network artifact used by an image build has a version-specific URL in
`toolchain.lock` and is verified before extraction. Maven is downloaded from
the permanent Apache Archive rather than a rotating current-release mirror.
Jenkins plugins are requested by the versions in `plugins.lock.txt` and every
downloaded JPI is checked against `plugins.sha256`.

The upstream locations are suitable as a reproducible fallback:

| Artifact | Immutable identity | Integrity check |
| --- | --- | --- |
| Controller, inbound agent, Docker proxy | registry tag plus OCI digest | registry digest |
| Jenkins plugins | plugin ID plus exact version | `plugins.sha256` |
| Node.js archives | exact version and architecture in path | SHA-256 |
| Maven archive | exact version in Apache Archive path | SHA-512 |
| Flutter archive | exact stable version in path | SHA-256 |
| Android command-line tools | exact release ID in path | SHA-256 |

## Internal mirror layout

Production installations should mirror all of the entries above before
building. Keep the same immutable hierarchy in the artifact registry:

```text
jenkins/plugins/<plugin-id>/<version>/<plugin-id>.hpi
nodejs/<version>/<archive>
maven/<version>/<archive>
flutter/<version>/<archive>
android/cmdline-tools/<release-id>/<archive>
```

Mirror the three base images by digest, not only by tag. Change only the URL or
registry fields in `toolchain.lock`; never remove or recalculate a checksum
from the mirrored file. A mirror promotion must fail if bytes fetched from
upstream do not match the committed checksum.

For Jenkins plugins, set `JENKINS_PLUGIN_DOWNLOAD_URL` to the mirror's
versioned plugin root. The mirror must implement the same
`/<plugin-id>/<version>/<plugin-id>.hpi` layout.
