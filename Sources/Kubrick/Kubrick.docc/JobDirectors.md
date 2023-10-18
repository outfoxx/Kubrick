# Job Directors

Details of coordination between principal and assistant Directors.

@Metadata {
  @PageColor(purple)
}


## Overview

Kubrick supports directing the execution of Jobs across coordinated processes allowing Jobs to be started in one
process and completed in another. The transfer of Jobs between Directors can be explicit or as a failsafe to complete
Jobs that don't complete in their original process.

## Modes

Directors operate in two modes "principal" and "assistant". Principals and assistants work together on the same
<doc:JobStore> to ensure that Jobs execute to completion across process restarts.

@Row {
  @Column(size: 2) {    
    Principal Directors not only execute the Jobs submitted to it but also watch the Job activity of assistants and
    will takes control of assistant Jobs when necessary to ensure the Jobs get completed. The design is specifically
    targeted at supporting applications and extensions working together, see <doc:#Applications-Extensions>.
    
    Each distinct Jobs store supports a single principal Director and as many assistant Directors as necessary.
    Multiple principal Directors can be ran simultaneously by using separate <doc:JobStore> instances.    
  }
  @Column {
    ![Diagram of principal and assistant directors working together](processes)
  }
}

To initialize multiple coordinating ``JobDirector`` instances, you pass the same ``JobDirectorID`` and location
Directory with differing ``JobDirectorMode`` values.

In one process we initialize the principal Director using the ``JobDirectorMode/principal`` mode:

```swift
let jobStoreLocation = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "com.example.app")!
let jobDirectorID = JobDirectorID("ExampleJobStore")!

let jobDirector = try JobDirector(id: jobDirectorID, location: jobStoreLocation, mode: .principal)
```

In another process we initialize an assistant Director using the same location and Director
ID, using the ``JobDirectorMode/assistant(name:)`` mode with a unique name for the assistant:

```swift
let jobStoreLocation = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "com.example.app")!
let jobDirectorID = JobDirectorID("ExampleJobStore")!

let jobDirector = try JobDirector(id: jobDirectorID, location: jobStoreLocation, mode: .assistant("Assistant1"))
```

At this point the principal and the assistant will work together and any Jobs that fail to complete in the assistant
will be completed by the principal Directory **automatically**. Additionally, the assistant can choose to transfer
Jobs to the principal explicitly.


## Job Transfers

Jobs transfer are uni-directional, they only transfer from assistant Directors to the principal Director; they never
transfer from a principal to an assistant.

Principal Directors automatically transfer Jobs from assistants when the assistant is stopped or its processes exits.
The is a failsafe to ensure long running Jobs in assistants are always processed to completion. There is nothing
special required to enable automatic transfers except to start the principal Director on process startup.

### Explicit Job transfers

Additionally, Jobs can be explicitly transferred to the principal Director by the assistant a Job is executing in. This
supports scenarios like starting Jobs that include background `URLSession` transfers in an assistant and completing
the Job in the principal Director, reusing the same Job definitions throughout.

To explicitly transfer a Job, the **Job** itself must call ``JobDirector/transferToPrincipal()``. If the Job is
currently being executed by an assistant Director, it will be transferred to the principal Director.

The following example shows an explicit transfer to the principal Director after starting a file download.

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

The primary function of having principal and assistant Directors is to coordinate work between a main application and
one or more extensions using the same Jobs for all scenarios. 

<doc:Explicit-job-transfers>, <doc:URLSessionJobs>, and <doc:UserNotificationJobs> all work together to make working
with applications and extensions easier. 
