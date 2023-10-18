# ``Kubrick``

Director for persistent, resilient, idempotent, asynchronous Jobs built on Swift concurrency.

@Metadata {
  @PageColor(purple)
  @PageImage(purpose: icon, source: logo)
}

## Overview

Kubrick directs the execution of long running groups of tasks known as **Jobs** providing the following properties:

@Row {
  @Column {
    @Image(source: guaranteed)
  }
  @Column(size: 5) {
    **Guaranteed**\
    Submitted Jobs progress to completion regardless of the amount of time required for them to complete.
  }
}
@Row {
  @Column {
    @Image(source: unique)
  }
  @Column(size: 5) {
    **Unique**\
    Each Job, and its tree of dependencies, are executed in a unique isolated context from all other Job trees.
  }
}
@Row {
  @Column {
    @Image(source: resiliant)
  }
  @Column(size: 5) {
    **Resilient**\
    Jobs are resilient across process restarts including explicit exit, system termination and crashes.
  }
}
@Row {
  @Column {
    @Image(source: idempotent)
  }
  @Column(size: 5) {
    **Idempotent**\
    Kubrick ensures Jobs only execute to completion _once_ even when being resurrected or transferred.
  }
}
@Row {
  @Column {
    @Image(source: transferable)
  }
  @Column(size: 5) {
    **Transferable**\
    Jobs started in one process _can_ be completed by other processes maintaining all other properties.
  }
}

### Concurrency

Jobs are built upon Swift's Concurrency and therefore are easy to write in a straightforward manner using 
`async`/`await`.

### Integrations

Kubrick provides deep integration for long running system services that make it easy to run code that prepares and/or 
relies on the results of these services without needing to manage restarts or worry about duplication.

Provided Integrations:
@Row {
  @Column {
    @Image(source: network)
  }
  @Column(size: 5) {
    **URL Session**\
    Upload and download transfer Jobs are provided that work with normal and background sessions. 
  }
}
@Row {
  @Column {
    @Image(source: notifications)
  }
  @Column(size: 5) {
    **User Notifications**\
    Provides Jobs that display user notifications and can wait for user actions before completing.
  }
}

## Topics

### Essentials

- <doc:GettingStarted>
