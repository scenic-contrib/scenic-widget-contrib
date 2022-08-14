# Contributing Guidelines

Fork-away & just make PRs! Sharing is caring!

We try to be very easy-going with any new components. However for any code
directly in `lib/` or in `lib/core/` there is a higher quality bar because those
are shared and used by other components.

Please read [[Development.md]]

## ScenicWidgets.Core

A small subset of code which may be shared between components, may be placed
under the `ScenicWidgets.Core` namespace. Modules places in this namespace
must contain *strictly pure-functions only!!* - common models may also
be placed under this namespace.
