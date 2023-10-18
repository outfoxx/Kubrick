# Getting Started

Basics of creating Jobs and submitting them to a JobDirector.

@Metadata {
  @PageColor(purple)
}

## Overview

Kubrick is a complex framework but generally easy to use. We will walk through the basics of building and submitting
Jobs to a Director.

- <doc:#Submitting-our-first-Job>
- <doc:#Job-with-an-input>
- <doc:#Job-with-a-dependency>
- <doc:#Dependency-injection>
- <doc:#Dynamically-executing-jobs>
- <doc:#A-lesson-in-Job-uniqueness>
- <doc:#Job-modifiers>

### What is a "Job"?

Jobs are types that implement one of the ``Job`` protocols, ``ResultJob`` or ``ExecutableJob`` depending on whether
your Job returns a result or not. Implementation is as simple as providing an `execute` method.

Jobs that can be submitted to a ``JobDirector`` are special, and must implement ``SubmittableJob``. Submittable Jobs
must be `Codable` and cannot return a result nor can they throw errors.


## Submitting our first Job

To get started, here is a basic ``SubmittableJob`` that simply prints "Hello from our Job!":

```swift
struct ExampleJob: SubmittableJob, Codable {

  func execute() async {
    print("Hello from our Job!")
  }

}
```

As referenced previously, all ``SubmittableJob`` implementations must be `Codable` this allows them to be
resurrected after the process restarts. To enable the ``JobDirector`` to load Jobs it requires a resolver to map your Job
types (e.g. `ExampleJob`) to a string "type id".

Kubrick provides a simple resolver, based on type names, that only needs a list of your Job types.

```swift
let jobTypeResolver = TypeNameTypeResolver(jobs: [
  ExampleJob.self
])
```

To submit our `ExampleJob` we need a ``JobDirector``. To create a ``JobDirector`` we need to provide
a location for the <doc:JobStore> (where the JobDirector saves the state of submitted Jobs) and the previously
created type resolver. Additionally, the Director must be started before it can accept Jobs.

```swift
let jobDirector = JobDirector(directory: FileManager.default.temporaryDirectory,
                              typeResolver: jobTypeResolver)

try await jobDirector.start()
```

With our created and started `jobDirector`, we can submit our `ExampleJob`.

```swift
try await jobDirector.submit(ExampleJob())
```

For all our setup, we should now see the result of our `ExampleJob`, in the console:

    Hello from our Job!

> Note: Job submission is fire-and-forget. And as there are no results or errors allowed from
``SubmittableJob``s, there is no method provided by Kubrick to check the status or outcome of submitted Jobs. This
responsibility is passed on to the implementor. If you want to track the completion of a submitted Job you need to use
some form of persistence (e.g. CoreData or serializing a `Codable` value to a file).


## Job with an input

Jobs are unique based upon their inputs. Any Job of the same type with the same input values will only be executed once
in the context of its root submitted Job. Kubrick determines this Job identity by hashing all of a Job's inputs.

You denote a Job's inputs by using the ``JobInput`` property wrapper. Here we add a message as an input to our
`ExampleJob`.

```swift
struct ExampleJob: SubmittableJob, Codable {

  @JobInput var message: String

  init(message: String) {
    self.message = message
  }

  func execute() async {
    print(message)
  }

  init(from decoder: Decoder) {
    // ... normal Decodable conformance
    self.init(message: message)
  }

  func encode(to encode: Encoder) {
    // ... normal Encodable conformance
  }

}
```

``JobInput``s can be assigned a constant value (as seen above) or be linked to the output of other Jobs (as we will
see later). As shown, we make sure to implement `Codable` as required and delegate to the `init(message:)` initializer
to ensure the Job's ``JobInput``s are properly restored during resurrection.

The new `ExampleJob` can be now be submitted using our new initializer.

```swift
try await jobDirector.submit(ExampleJob(message: "Hello from our Job!"))
```

> Warning: ``JobInput`` values cannot be read outside of a Job's `execute` method. Any attempt to do so will result in
a fatal assertion failure.

> Note: All ``JobInput`` values must be ``JobHashable``. Kubrick uses a hash of the ``JobInput`` values, that is
stable across process restarts, as the identity for the Job. Out of the box most common Swift types conform to
``JobHashable`` as well as any type that conforms to `Encodable`.  


## Job with a dependency

Instead of assigning a constant value to a ``JobInput``, they can also be bound to the result of a dependent Job. To
bind an input to a dependent Job, the `bind(job:)` method of the input's projected value is used.

```swift
self.$input.bind(job: SomeJob())
```

Now we will add a `GenerateMessageJob` to our example that produces a message with a random value and bind that to the
`message` input of our `ExampleJob`.

```swift
struct GenerateMessageJob: ResultJob {
  
  func execute() async throws -> String {
    return "A random hello \(Int.random(in: .min ... .max))"
  }

}

struct ExampleJob: SubmittableJob, Codable {

  @JobInput var message: String

  init() {
    self.$message.bind(job: GenerateMessageJob())
  }

  func execute() async {
    print(message)
  }

  init(from decoder: Decoder) {
    self.init()
  }

  func encode(to encode: Encoder) {
  }

}
```

We now have a "tree of Jobs" where our submittable `ExampleJob` is the root. Submitting the root `ExampleJob`
will cause the dependent `GenerateMessageJob` to be executed first and only when its `execute` method has been
successfully run to completion will the `execute` method of `ExampleJob` be executed.

Only ``SubmittableJob`` implementations need to be `Codable`. Dependent Jobs are always deserialized as
part of the Job tree formed from the root ``SubmittableJob``. This lessens the number of `Codable` implementations
required.

> Note: If any of a Job's dependencies fail, its `execute` method will never be called. When a Job executes all of
the `JobInput`s will have valid values. Failing inputs can be handled using the ``Job/catch(handler:)`` or 
``Job/mapToResult()`` modifiers.


## Dependency injection

Kubrick has integrated dependency injection capabilities that are backed by the Director executing the Job.

The ``JobInject`` property wrapper is used to inject a dependency value. Injection is based on the type of the value
being injected and, optionally, `String` or `String` enum based "tags" to differentiate different values of the same
type. 

Here we change our example to inject the message we print instead of passing it in or generating it via a dependent Job
as in the previous examples.

```swift
struct ExampleJob: SubmittableJob, Codable {

  @JobInject(tags: "message") var message: String

  func execute() async {
    print(message)
  }

  init(from decoder: Decoder) {
  }

  func encode(to encode: Encoder) {
  }

}
```

To use ``JobInject`` the value must first be configured on the Director via its ``JobDirector/injected`` property.

```swift
jobDirector.injected[String.self, tags: "message"] = "Hello from our Job!"
```

Now when our `ExampleJob` is executed the `message` will be injected from the value we setup on the Director.


## Dynamically executing Jobs

Sometimes Jobs must be executed during the execution of a Job itself, for this Kubrick provides the
``DynamicJobDirector``. The ``DynamicJobDirector`` is provided via the environment injection property wrapper
``JobEnvironmentValue``.

Here is our adapted example that runs a dependent Job dynamically that does the printing we previously were doing
in the `execute` method.

```swift
struct PrintMessageJob: ExecutableJob {

  @JobInput var message: String

  input(message: String) {
    self.message = message
  }

  func execute() async throws {
    print(message)
  }

}

struct ExampleJob: SubmittableJob, Codable {

  @JobEnvironmentValue(\.dynamicJobs) var dynamicJobs

  func execute() async {
    _ = await dynamicJobs.result(for: PrintMessageJob(message: "Hello from our Job!"))
  }

  init(from decoder: Decoder) {
  }

  func encode(to encode: Encoder) {
  }

}
```

> Tip: Dependent Jobs bound to ``JobInput``s are executed in parallel automatically. To execute dynamic Jobs in
parallel, one of Swift's concurrency primitives (`async let` or `with(Throwing)TaskGroup`) must be used.


## A lesson in Job uniqueness

Jobs can, and should, be broken apart as needed. Jobs are guaranteed to be executed to completion only once and
breaking them into separate Jobs allows a large complex tree of Jobs to be restarted without repeating any of the Jobs
that have already executed to completion.

- Important: A Job must be executed to completion to ensure it is not executed again after a restart. Jobs that
are in the process of executing when its process is restarted will have its `execute` method called again to allow it
to complete its run. Any task that should never be executed twice, should be done in a dependent or dynamic Job.

As has been stated before, a Job's identity is formed by the hash of its "type" and all its input values
(after dependencies have been resolved to result values).

As an example of this uniqueness, we will repurpose the example used for dynamic Jobs to show an example of the
``JobDirector`` not executing Jobs more than once.

This example uses dynamic Jobs to call the `PrintMessageJob` Job three times. Two of those dynamic Jobs have the same
message input and a third dynamic Job has a different message.

```swift
struct PrintMessageJob: ExecutableJob {

  @JobInput var message: String

  input(message: String) {
    self.message = message
  }

  func execute() async throws {
    print(message)
  }

}

struct ExampleJob: SubmittableJob, Codable {

  @JobEnvironmentValue(\.dynamicJobs) var dynamicJobs

  func execute() async {
    _ = await dynamicJobs.result(for: PrintMessageJob(message: "First message!"))
    _ = await dynamicJobs.result(for: PrintMessageJob(message: "First message!"))
    _ = await dynamicJobs.result(for: PrintMessageJob(message: "Second message!"))
  }

  init(from decoder: Decoder) {
  }

  func encode(to encode: Encoder) {
  }

}
```

Submitting our new `ExampleJob` as normal...

```swift
try await jobDirector.submit(ExampleJob())
```

will print the following:

    First message!
    Second message!


Examining what is happening, the `PrintMessageJob` has just the single input `message`. Since Kubrick determines a Job's
identity by hashing the inputs of the Job. The first two dynamic Jobs yield the same hash and therefore have the same
Job identity. Continuing on, since each unique Job only executes to completion once, the second duplicated Job will not
be executed because in the eyes of the `JobDirector` it has already been completed.

Job uniqueness is determined in the context of the root `SubmittableJob` that was submitted to the Director.
Given this, resubmitting the current `ExampleJob` to the Director _**will**_ execute the Job and its dependencies
again, printing the same messages as before.

## Job modifiers

Kubrick provides Job "modifiers" to handle specific cases like mapping results and retrying Jobs. Job modifiers
are applied in a builder style similar to SwiftUI view modifiers.

> Tip: These examples using the result builder style ``JobBinding/bind(builder:)`` method. You can read more about it
at <doc:BindingDependentJobs>.

### Retrys

Jobs can be retried upon failure using the ``Job/retry(maxAttempts:)`` or ``Job/retry(filter:)`` modifier. If a Job
retries the maximum # of times the last failure is reported.

Here is a simple example of a contrived `DataJob` where its execution is attempted 3 times. 

```swift
struct ExampleJob: SubmittableJob, Codable {
  
  @JobInput var retried: Data

  init() {
    self.$retried.bind {
      DataJob()
        .retry(maxAttempts: 3)
    }
  }
  
  // Codable implementation ... 
}
```


### Catch errors

A Job can use the ``Job/catch(handler:)`` modifier to map any failures to a default or similar value.

The following example maps any errors from the `RandomIntJob` to the value -1. 

```swift
struct ExampleJob: SubmittableJob, Codable {

  @JobInput var random: Int

  init() {
    self.$random.bind {
      RandomIntJob()
        .catch { _ in return -1 }
    }
  }

  // implementation ... 
}
```

In contrast to "normal" processing, where the failure of a dependent Job means the Job's execute method is never
called, using ``Job/catch(handler:)`` ensures the Job's `execute` method will be called even if the dependency failed.


### Map results

The ``Job/map(_:)`` modifier will map a Job's result to another value; similar to Swift's built in `map` methods.

The following example maps an integer from the `RandomIntJob` to its String equivalent. 

```swift
struct ExampleJob: SubmittableJob, Codable {

  @JobInput var random: String

  init() {
    self.$random.bind {
      RandomIntJob()
        .map { String($0) }
    }
  }

  // implementation ... 
}
```

### Map/catch a Job's result value or error

``Job/mapToResult()`` maps the result of the Job's execute method or any error it throws to a standard `Result`.

The following example maps an integer from the `RandomIntJob` to its String equivalent. 

```swift
struct ExampleJob: SubmittableJob, Codable {

  @JobInput var random: Result<Int, Error>

  init() {
    self.$random.bind {
      RandomIntJob()
        .mapToResult()
    }
  }

  // implementation ... 
}
```

In contrast to "normal" processing, where the failure of a dependent Job means the Job's execute method is never
called, using `Job/mapToResult()` ensures the Job's `execute` method will be called even if the dependency failed and
allows inspection of the error during execution.


## Where to go next...

That covers the basics of Kubrick's Job capabilities. Check out the following resources to learn more about Kubrick's
setting up and using Kubrick.

- <doc:BindingDependentJobs>
- <doc:JobDirectors>

