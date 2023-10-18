# Binding Dependent Jobs

Details of the different ways to bind Dependent Jobs to inputs.

@Metadata {
  @PageColor(purple)
}

## Overview

Kubrick Job dependencies can be bound to ``JobInput`` values in a number of ways. The basic rule for binding a Job
result to a Job input is that the the generic types _must_ match.   

While the result and input value are required to match, there are methods for handling optionals and even a builder
API that makes it easy to bind using different types.

> Note: It's important to not that ``JobInput`` values _must_ be bound in the Job's initializer. Attempting execution
of a Job with unbound input will cause an error to be thrown.


## Binding to a constant

``JobInput`` values can be bound to constants using the ``JobBinding/bind(value:)``. 

```swift
struct RandomIntJob: ResultJob {} // Returns `Int`

struct ExampleJob: SubmittableJob, Codable {

  @JobInput var integer: Int

  init() {
    self.$integer.bind(value: 10)
  }

}
```

> Tip: ``JobInput`` values support much easier binding for constants using the assignment operator!
```swift
self.integer = 10
```


## Binding to a Job result

The simplest method used to bind inputs to Job results is using the ``JobBinding/bind(job:)-87syz``.

```swift
struct RandomIntJob: ResultJob {} // Returns `Int`

struct ExampleJob: SubmittableJob, Codable {

  @JobInput var integer: Int

  init() {
    self.$integer.bind(job: RandomIntJob())
  }

}
```

### Optional Jobs to optional inputs

When binding to an optional input value, the ``JobBinding/bind(job:)-5sr2w`` function allows
passing an optional Job itself, which it will map to an optional Job result.

```swift
struct RandomIntJob: ResultJob {} // Returns `Int`

struct ExampleJob: SubmittableJob, Codable {

  @JobInput var integer: Int?

  init(shouldBind: Bool) {
    self.$integer.bind(job: shouldBind ? RandomIntJob() : nil)
  }

}
```

## Binding using the Job builder

Kubrick provides the ``JobBinding/bind(builder:)`` result builder to allow easier binding when the Job type may be
different (e.g. `if`/`else` or `switch`).

Using `if`/`else`...
```swift
struct ConstantIntJob: ResultJob {} // Returns `Int`
struct RandomIntJob: ResultJob {} // Returns `Int`

struct ExampleJob: SubmittableJob, Codable {

  @JobInput var integer: Int?

  init(useRandom: Bool) {
    self.$integer.bind {
      if useRandom {
        RandomIntJob()
      }
      else {
        ConstantIntJob()
      }
    }
  }

}
```
