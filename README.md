# SelectCopy

A tiny macOS menu bar app that copies selected text to the clipboard as soon as you finish selecting it (drag, double-click, or triple-click), the way X11 terminals do.

It reads the selection through the Accessibility API. For apps that don't expose their selection (Chrome, Electron, …), it sends a Cmd+C instead. It skips Finder, where Cmd+C copies files, and WezTerm, which already copies on select.

## Build & install

```sh
./build.sh
```

This compiles `main.swift`, signs the app ad-hoc, and installs it to `/Applications/SelectCopy.app`. On first launch, grant Accessibility access in System Settings → Privacy & Security → Accessibility.

The menu bar menu has toggles for Copy on Select, a ✅ flash on copy, and Launch at Login.

Requires macOS 13+.

## License

MIT, see [LICENSE](LICENSE).
