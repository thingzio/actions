# Fixture for the build-docker selftest.
#
# Pinned to a digest rather than a tag, which is the rule this repository asks
# of every consumer: a tag is mutable, so `alpine:3.22` today and `alpine:3.22`
# tomorrow are not necessarily the same bytes, and a build that cannot be
# reproduced cannot be meaningfully attested. The digest is the multi-platform
# index, so both linux/amd64 and linux/arm64 resolve from it.
#
# Kept trivial on purpose: the selftest is proving the pipeline, not the image.
FROM alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce

ARG SELFTEST_MESSAGE="thingzio selftest"

RUN printf '%s\n' "${SELFTEST_MESSAGE}" >/etc/thingz-selftest

ENTRYPOINT ["/bin/sh", "-c", "cat /etc/thingz-selftest && uname -m"]
