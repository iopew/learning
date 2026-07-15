package main

import "fmt"

// Step 1: Define the interface — a contract that says
// "anything with a Speak() string method is a Speaker"
type Speaker interface {
    Speak() string
}

// Step 2: Define some types that have nothing to do with each other
type Dog struct {
    Name string
}

// Dog has a Speak method — so Dog satisfies Speaker automatically
func (d Dog) Speak() string {
    return d.Name + " says woof!"
}

type Cat struct {
    Name string
}

// Cat also has a Speak method — so Cat satisfies Speaker too
func (c Cat) Speak() string {
    return c.Name + " says meow!"
}

type Clock struct{}

// Clock also has a Speak method
func (c Clock) Speak() string {
    return "tick tock"
}

// Step 3: A function that accepts ANY Speaker
// It doesn't care WHAT the type is — only that it can Speak()
func PrintSound(s Speaker) {
    fmt.Println(s.Speak())
}

func main() {
    // Create instances of each type
    dog := Dog{Name: "Rex"}
    cat := Cat{Name: "Luna"}
    clock := Clock{}

    // Pass each one to the SAME function
    PrintSound(dog)   // Rex says woof!
    PrintSound(cat)   // Luna says meow!
    PrintSound(clock) // tick tock
}
