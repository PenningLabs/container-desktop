import Foundation
import Observation

@Observable
final class DNSViewModel {

    private let dnsService: CLIDNSService

    var domains: [String] = []
    var isLoading: Bool = false
    var error: AppError?
    var showCreateSheet: Bool = false
    var showDeleteConfirmation: Bool = false
    var domainToDelete: String?

    init(dnsService: CLIDNSService) {
        self.dnsService = dnsService
    }

    func loadDomains() async {
        isLoading = true
        defer { isLoading = false }
        do {
            domains = try await dnsService.listDomains()
            error = nil
        } catch {
            self.error = .loadFailed(error)
        }
    }

    func createDomain(_ name: String) async {
        do {
            try await dnsService.createDomain(name)
            await loadDomains()
            showCreateSheet = false
        } catch {
            AppEventLog.shared.error(error, context: "Failed to create DNS domain '\(name)'", source: "DNS")
            self.error = .actionFailed("create DNS domain", error)
        }
    }

    func confirmDelete(_ domain: String) {
        domainToDelete = domain
        showDeleteConfirmation = true
    }

    func executeDelete() async {
        guard let domain = domainToDelete else { return }
        do {
            try await dnsService.deleteDomain(domain)
            await loadDomains()
            showDeleteConfirmation = false
            domainToDelete = nil
        } catch {
            AppEventLog.shared.error(error, context: "Failed to delete DNS domain '\(domain)'", source: "DNS")
            self.error = .actionFailed("delete DNS domain", error)
        }
    }
}
