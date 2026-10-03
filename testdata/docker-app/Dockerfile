# Fixture for the build-docker selftest.
#
# Pinned to a digest rather than a tag, which is the rule this repository asks
# of every consumer: a tag is mutable, so `alpine:3.22` today and `alpine:3.22`
# tomorrow are not necessarily the same bytes, and a build that cannot be
# reproduced cannot be meaningfully attested. The digest is the multi-platform
# index, so both linux/amd64 and linux/arm64 resolve from it.
#
# Kept trivial on purpose: the selftest is proving the pipeline, not the image.
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

ARG SELFTEST_MESSAGE="thingzio selftest"

RUN printf '%s\n' "${SELFTEST_MESSAGE}" >/etc/thingz-selftest

ENTRYPOINT ["/bin/sh", "-c", "cat /etc/thingz-selftest && uname -m"]
