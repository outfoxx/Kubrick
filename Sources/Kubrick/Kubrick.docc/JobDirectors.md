# Job Directors

Details of coordination between principal and assistant directors.

@Metadata {
  @PageColor(purple)
}


## Overview

Kubrick supports directing the execution of jobs across coordinated processes allowing jobs to be started in one
process and completed in another. The transfer of jobs between directors can be explicit or as a failsafe to complete
jobs that don't complete in their original process.

## Modes

Directors operate in two modes "principal" and "assistant". Principals and assistants work together on the same
<doc:JobStore> to ensure that jobs execute to completion across process restarts.

@Row {
  @Column(size: 2) {    
    Principal directors not only execute the jobs submitted to it but also watch the job activity of assistants and
    will takes control of assistant jobs when necessary to ensure the jobs get completed. The design is specifically
    targeted at supporting applications and extensions working together, see <doc:#Applications-Extensions>.
    
    Each distinct jobs store supports a single principal director and as many assistant directors as necessary.
    Multiple principal directors can be ran simultaneously by using separate <doc:JobStore> instances.    
  }
  @Column {
    ![Diagram of principal and assistant directors working together](processes)
  }
}

To initialize multiple coordinating ``JobDirector`` instances, you pass the same ``JobDirectorID`` and location
directory with differing ``JobDirectorMode`` values.

In one process we initialize the principal director using the ``JobDirectorMode/principal`` mode:

```swift
let jobStoreLocation = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "com.example.app")!
let jobDirectorID = JobDirectorID("ExampleJobStore")!

let jobDirector = try JobDirector(id: jobDirectorID, location: jobStoreLocation, mode: .principal)
```

In another process we initialize an assistant director using the same location and director
ID, using the ``JobDirectorMode/assistant(name:)`` mode with a unique name for the assistant:

```swift
let jobStoreLocation = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "com.example.app")!
let jobDirectorID = JobDirectorID("ExampleJobStore")!

let jobDirector = try JobDirector(id: jobDirectorID, location: jobStoreLocation, mode: .assistant("Assistant1"))
```

At this point the principal and the assistant will work together and any jobs that fail to complete in the assistant
will be completed by the principal directory **automatically**. Additionally, the assistant can choose to transfer
jobs to the principal explicitly.


## Job Transfers

Jobs transfer are uni-directional, they only transfer from assistant directors to the principal director; they never
transfer from a principal to an assistant.

Principal directors automatically transfer jobs from assistants when the assistant is stopped or its processes exits.
The is a failsafe to ensure long running jobs in assistants are always processed to completion. There is nothing
special required to enable automatic transfers except to start the principal director on process startup.

### Explicit job transfers

Additionally, jobs can be explicitly transfered to the principal director by the assistant a job is executing in. This
supports scenarios like starting jobs that include background `URLSession` transfers in an assistant and completing
the job in the principal director, reusing the same job definitions throughout.

To explicily transfer a job, the **job** itself must call ``JobDirector/transferToPrincipal()``. If the job is
currently being executed by an assistant director, it will be transfered to the principal director.

The following example shows an explicit transfer to the principal director after starting a file download.

```swift
struct ExampleJob: SubmittableJob, Codable {
  
  @JobInput var downloadedFile: URL
  
  @JobEnvironmentValue(\.currentJobDirector) var director
  
  init() {
    self.$downloadedFile.bind {
      URLSessionDownloadFileJob()
        .request(URLRequest(url: URL("https://example.com/some/file")))
        .onStart {
          try director.transferToPrincipal()
        }
    }
  }
  
  func execute() async {
    print("Downloaded file URL", downloadedFile)
  }
  
}
```

> Note: This example is fairly advanced and uses <doc:URLSessionJobs> that are setup to use a background `URLSession`
and relies on the session being configured to launch the main application to process background session events. 


## Applications & Extensions

The primary function of having principal and assistant directors is to coordinate work between a main application and
one or more extensions using the same jobs for all scenarios. 

<doc:Explicit-job-transfers>, <doc:URLSessionJobs>, and <doc:UserNotificationJobs> all work together to make working
with applications and extensions easier. 
