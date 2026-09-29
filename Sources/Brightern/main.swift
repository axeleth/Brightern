import Foundation
import ServiceManagement

// `Brightern --unregister-login-item` is used by scripts/uninstall.sh.
if CommandLine.arguments.contains("--unregister-login-item") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

BrighternApp.main()
