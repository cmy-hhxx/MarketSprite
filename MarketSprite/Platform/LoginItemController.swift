import Combine
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var message: String?
    @Published private(set) var isUpdating = false

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        status = service.status
        message = nil
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        guard !isUpdating, enabled != isEnabled else { return }
        isUpdating = true
        defer { isUpdating = false }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            status = service.status
            message = enabled ? Self.enableMessage(for: status) : nil
        } catch {
            status = service.status
            message = String(
                format: tr("无法更新登录启动：%@"),
                error.localizedDescription
            )
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func enableMessage(for status: SMAppService.Status) -> String? {
        switch status {
        case .enabled:
            nil
        case .requiresApproval:
            tr("已请求登录时启动，请在系统设置的“登录项”中允许。")
        case .notFound, .notRegistered:
            tr("登录启动未在系统中生效，请稍后重试。")
        @unknown default:
            tr("无法确认登录启动状态。")
        }
    }
}
