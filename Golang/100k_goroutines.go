package main

import (
	"fmt"
	"runtime"
	"sync"
	"time"
)

func main() {
	const n = 100_000
	var wg sync.WaitGroup

	before := runtime.NumGoroutine()
	fmt.Printf("Goroutines before: %d\n", before)

	for i := range n {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			time.Sleep(time.Second)
		}(i)
	}

	after := runtime.NumGoroutine()
	fmt.Printf("Goroutines after spawn: %d\n", after)

	wg.Wait()

	// open http://localhost:6060/debug/pprof/goroutine for detailed view
	fmt.Println("Done. All goroutines finished.")
}
