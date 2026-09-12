// Fixture module for the build-ko selftest. Deliberately has no third-party
// dependencies, which also exercises the workflow's handling of a module with
// no go.sum -- setup-go fails rather than degrading when module caching is on
// and it cannot find a lock file.
module github.com/thingzio/actions/testdata/go-app

go 1.24
