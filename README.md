# Pixel-Companion
Native macOS notch companion for agent runtimes, with an optional Pixel HQ/Paperclip connector.

## Build and run

Requires macOS 14+ and Xcode 16+. No dependencies, accounts or keys.

```sh
swift run PixelCompanion   # launch the app (or: open Package.swift in Xcode and press ⌘R)
swift test                 # unit tests
```

The companion lives in the MacBook notch, or in the menu bar on Macs without one. Hover for a
snapshot, click for details, and use **Settings…** to switch the connector, simulate connection
states, and choose notch or menu bar. This release ships only a `MockConnector`; it is read-only and
needs no Pixel HQ or other service.

- [Building and running](docs/BUILDING.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Connector interfaces](docs/CONNECTORS.md)
- [QA test plan](docs/QA_TEST_PLAN.md)

## Quality gate

Every change passes native checks, Greptile review and QA acceptance before merge. See [docs/QUALITY_GATE.md](docs/QUALITY_GATE.md).
