# Fixture the terraform-scan selftest scans for real.
#
# Deliberately clean at HIGH and CRITICAL: the selftest asserts that a
# well-formed module produces no findings and a zero exit code. A fixture with
# planted findings would make the selftest assert the scanner's ruleset instead
# of the workflow, and would break on every Trivy bump that retunes a check.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

resource "local_file" "fixture" {
  content  = "thingzio actions selftest"
  filename = "${path.module}/fixture.txt"

  # 0600 rather than the default: Trivy flags world-readable file permissions,
  # and the point of this fixture is to be clean.
  file_permission = "0600"
}
