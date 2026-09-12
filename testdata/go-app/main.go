// Command go-app is the fixture the build-ko selftest builds.
//
// It exists to be compiled, containerized, signed and verified, so it stays as
// small as a runnable Go program can be. It prints its build platform so a
// human inspecting a published selftest image can confirm which architecture
// they pulled.
package main

import (
	"fmt"
	"runtime"
)

func main() {
	fmt.Printf("thingzio selftest: %s/%s\n", runtime.GOOS, runtime.GOARCH)
}
